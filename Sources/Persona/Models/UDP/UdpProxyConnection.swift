//
//  UdpProxyConnection.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/5/23.
//

import Logging
import Foundation

import InternetProtocols
import Puppy
import Net
import TransmissionAsync

public class UdpProxyConnection
{
    // These static properties and functions handle caching connections to the udpproxy subsystem.
    // We need one connection to the udpproxy subsystem for each source address/port pair.
    static var connections: [UdpIdentity: UdpProxyConnection] = [:]

    static public func getConnection(identity: UdpIdentity, downstream: AsyncConnection, logger: Logger, udpLogger: Puppy, writeLogger: Puppy) async throws -> UdpProxyConnection
    {
        if let connection = Self.connections[identity]
        {
            return connection
        }
        else
        {
            let connection = try await UdpProxyConnection(identity: identity, downstream: downstream, logger: logger, udpLogger: udpLogger, writeLogger: writeLogger)
            Self.connections[identity] = connection
            return connection
        }
    }

    static public func removeConnection(identity: UdpIdentity)
    {
        self.connections.removeValue(forKey: identity)
    }

    static public func getConnections() -> [UdpProxyConnection]
    {
        return [UdpProxyConnection](self.connections.values)
    }
    // End of static section

    public let identity: UdpIdentity
    public let downstream: AsyncConnection
    public let upstream: AsyncConnection
    public let logger: Logger
    public let udpLogger: Puppy
    public let writeLogger: Puppy

    public var lastUsed: Date

    public init(identity: UdpIdentity, downstream: AsyncConnection, logger: Logger, udpLogger: Puppy, writeLogger: Puppy) async throws
    {
        self.identity = identity
        self.downstream = downstream
        self.logger = logger
        self.udpLogger = udpLogger
        self.writeLogger = writeLogger

        // Connect to the udpproxy subsystem. Note that each client gets its own udpproxy instance.
        // Also note that we only need one udpproxy instance for each source address/port pair.
        // This is so that we can route traffic from upstream to downstream correctly.
        // The udpproxy subsystem is running locally under systemd, so we make a TCP connection to its port.
        self.upstream = try await AsyncTcpSocketConnection("127.0.0.1", 1233, self.logger, verbose: false)
        self.lastUsed = Date()
    }

    // This is called by UdpProxy whenever we have a UDP packet to send upstream.
    public func writeUpstream(ipv4: IPv4, udp: UDP, payload: Data) async throws
    {
        // This will effectively reset the cleanup timer. The timing of cleanup doesn't need to be exact.
        self.lastUsed = Date()

        let hostBytes = ipv4.destinationAddress
        guard let portBytes = udp.destinationPort.maybeNetworkData else
        {
            throw UdpProxyError.dataConversionFailed
        }

        // Here is where we actually write the UDP packet to the udpproxy subsystem.
        // udpproxy subsystem expects (4-byte address, 2-byte port, and 4-byte length prefix + payload)
        try await self.upstream.write(hostBytes)
        try await self.upstream.write(portBytes)
        try await self.upstream.writeWithLengthPrefix(payload, 32)
    }

    func readUpstream() async throws -> (IPv4, UDP, Data)?
    {
        // udpproxy gives us (4-byte address, 2-byte port, and 4-byte length prefix + payload)
        self.logger.trace("UdpProxyConnection.readUpstream() - read 4")
        let hostBytes = try await self.upstream.readSize(4)
        self.logger.trace("UdpProxyConnection.readUpstream() - read 2")
        let portBytes = try await self.upstream.readSize(2)
        self.logger.trace("UdpProxyConnection.readUpstream() - read with length prefix")
        let payload = try await self.upstream.readWithLengthPrefix(prefixSizeInBits: 32)

        self.logger.trace("UdpProxyConnection.readUpstream() ended")
        return try await self.processUpstreamData(hostBytes, portBytes, payload)
    }

    // Here we process the raw data we got from the udpproxy subsystem. If it checks out, we send it downstream.
    func processUpstreamData(_ hostBytes: Data, _ portBytes: Data, _ payload: Data) async throws -> (IPv4, UDP, Data)?
    {
        guard let sourceAddress = IPv4Address(data: hostBytes) else
        {
            throw UdpProxyError.dataConversionFailed
        }

        guard let sourcePort = portBytes.maybeNetworkUint16 else
        {
            throw UdpProxyError.dataConversionFailed
        }

        guard payload.count > 0 else
        {
            return nil
        }

        // Here we do NAT translation on the UDP layer, adding the stored destination port.
        // This is why we need one udpproxy instance per address/port pair.
        guard let udp = InternetProtocols.UDP(sourcePort: sourcePort, destinationPort: self.identity.localPort, payload: payload) else
        {
            self.logger.error("UdpProxyConnection.processRemoteData - failed to make a UDP packet")
            return nil
        }

        // Here we do NAT translation on the IPv4 layer, adding the stored destination address.
        // This is why we need one udpproxy instance per address/port pair.
        guard let ipv4 = try InternetProtocols.IPv4(sourceAddress: sourceAddress, destinationAddress: self.identity.localAddress, payload: udp.data, protocolNumber: InternetProtocols.IPprotocolNumber.UDP) else
        {
            self.logger.error("UdpProxyConnection.processRemoteData - failed to make a IPv4 packet")
            return nil
        }

        return (ipv4, udp, payload)
    }

    public func pump() async throws -> (IPv4, UDP, Data)?
    {
        self.logger.trace("pumping UDP")

        try await self.upstream.write(Data(array: [0, 0, 0, 0]))
        try await self.upstream.write(Data(array: [0, 0]))
        try await self.upstream.writeWithLengthPrefix(Data(), 32)

        if let result = try await self.readUpstream()
        {
            self.lastUsed = Date() // now
            return result
        }
        else
        {
            return nil
        }
    }

    public func close() async throws
    {
        try await self.upstream.write(Data(array: [0, 0, 0, 0]))
        try await self.upstream.write(Data(array: [0, 1]))
        try await self.upstream.writeWithLengthPrefix(Data(), 32)

        try await self.upstream.close()
        UdpProxyConnection.removeConnection(identity: self.identity)
    }

    // Check if the UDP proxy has timed out.
    // UDP connections never explictly close, so we time them out instead.
    func checkForCleanup() async throws
    {
        let now = Date().timeIntervalSince1970
        let then = self.lastUsed.timeIntervalSince1970
        let elapsed = now - then

        self.logger.trace("UdpProxyConnection.checkForCleanup \(now) - \(then) = \(elapsed)/\(UdpProxy.udpTimeout)...")

        if elapsed > UdpProxy.udpTimeout
        {
            self.logger.trace("UdpProxyConnection.checkForCleanup closing connection for \(self.identity.localAddress.string):\(self.identity.localPort)")
            self.udpLogger.trace("UdpProxyConnection.checkForCleanup closing connection for \(self.identity.localAddress.string):\(self.identity.localPort)")

            // Send close signal
            try await self.close()
        }
    }
}
