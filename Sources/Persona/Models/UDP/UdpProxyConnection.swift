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
    // End of static section

    public let identity: UdpIdentity
    public let downstream: AsyncConnection
    public let upstream: AsyncConnection
    public let logger: Logger
    public let udpLogger: Puppy
    public let writeLogger: Puppy

    public var lastUsed: Date
    public var cleanupTimer: Timer? = nil

    var running: Bool = true

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
        self.upstream = try await AsyncTcpSocketConnection("127.0.0.1", 1233, self.logger)
        self.lastUsed = Date()

        // UDP connections never explictly close, so we create a timer to time them out instead.
        self.cleanupTimer = Timer.scheduledTimer(withTimeInterval: UdpProxy.udpTimeout, repeats: true)
        {
            timer in

            self.checkForCleanup(timer: timer)
        }

        // We can receive upstream packets from the udpproxy subsystem at any time, so we start a task to wait.
        // Note that we won't receive any upstream packets if we don't have an active UdpProxyConnection.
        // So it takes at least one downstream UDP packet to activation receiving packets from upstream.
        // If we don't keep receiving downstream packets, eventually all of the UdpProxyConnections will time out.
        Task
        {
            do
            {
                try await self.readUpstream()
            }
            catch
            {
                self.logger.error("UdpProxy.pumpRemote failed : \(error) - \(error.localizedDescription)")
            }
        }
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

        // udpproxy subsystem expects 4-byte length prefix + (4-byte address, 2-byte port, and payload)
        let bytes = hostBytes + portBytes + payload

        self.logger.debug("Writing \(bytes.count) bytes to the UDP Proxy Server: \(bytes.hex)")

        if udp.destinationPort == 7
        {
            self.udpLogger.debug("Writing \(bytes.count) bytes to the UDP Proxy Server: \(bytes.hex)")
        }

        // Here is where we actually write the UDP packet to the udpproxy subsystem.
        try await self.upstream.writeWithLengthPrefix(bytes, 32)

        self.logger.debug("Wrote \(bytes.count) bytes to the UDP Proxy Server:")

        if udp.destinationPort == 7
        {
            self.udpLogger.debug("Wrote \(bytes.count) bytes to the UDP Proxy Server:")
        }
    }

    // This runs in a loop in its own task. We can received UDP packets from the udpproxy subsystem at any time.
    func readUpstream() async throws
    {
        self.logger.debug("UdpProxy.pumpRemote()")
        while self.running
        {
            self.logger.debug("UdpProxy.pumpRemote() - readWithLengthPrefix(32)")
            self.udpLogger.info("persona <- udpproxy - trying to read")

            // udpproxy gives us 4-byte length prefix + (4-byte address, 2-byte port, and payload)
            let data = try await self.upstream.readWithLengthPrefix(prefixSizeInBits: 32)

            self.logger.debug("UdpProxyConnection.pumpRemote() - read \(data.count)")
            self.udpLogger.info("persona <- udpproxy - read \(data.count) bytes")

            try await self.processUpstreamData(data)
        }

        try await self.upstream.close()
    }

    // Here we process the raw data we got from the udpproxy subsystem. If it checks out, we send it downstream.
    func processUpstreamData(_ data: Data) async throws
    {
        self.logger.trace("UDP Proxy Server Gave Us Data: (\(data.count) - \(data.hex))")

        // udpproxy gives us 4-byte length prefix + (4-byte address, 2-byte port, and payload)
        // The 4-byte prefix was already stripped on the read.
        // This leaves us with 4-byte address, 2-byte port, and payload.
        // So we need more than 6 bytes if there is a payload.
        // We don't support UDP packets that don't have a payload.
        guard data.count > 6 else
        {
            throw UdpProxyError.badUdpProxyResponse
        }
        
        // udpproxy gives us 4-byte length prefix + (4-byte address, 2-byte port, and payload)
        // The 4-byte prefix was already stripped on the read.
        // This leaves us with 4-byte address, 2-byte port, and payload.
        let sourceAddressBytes = Data(data[0..<4])
        let sourcePortBytes = Data(data[4..<6])
        let payload = Data(data[6...])

        guard let sourceAddress = IPv4Address(data: sourceAddressBytes) else
        {
            throw UdpProxyError.dataConversionFailed
        }

        guard let sourcePort = sourcePortBytes.maybeNetworkUint16 else
        {
            throw UdpProxyError.dataConversionFailed
        }

        if sourcePort == 7
        {
            self.udpLogger.trace("UdpProxyConnection.processRemoteData(\(data.count) - \(data.hex))")
        }

        // Here we do NAT translation on the UDP layer, adding the stored destination port.
        // This is why we need one udpproxy instance per address/port pair.
        guard let udp = InternetProtocols.UDP(sourcePort: sourcePort, destinationPort: self.identity.localPort, payload: payload) else
        {
            self.logger.error("UdpProxyConnection.processRemoteData - failed to make a UDP packet")
            return
        }

        // Here we do NAT translation on the IPv4 layer, adding the stored destination address.
        // This is why we need one udpproxy instance per address/port pair.
        guard let ipv4 = try InternetProtocols.IPv4(sourceAddress: sourceAddress, destinationAddress: self.identity.localAddress, payload: udp.data, protocolNumber: InternetProtocols.IPprotocolNumber.UDP) else
        {
            self.logger.error("UdpProxyConnection.processRemoteData - failed to make a IPv4 packet")
            return
        }

        if sourcePort == 7
        {
            self.logger.trace("UdpProxyConnection.processRemoteData - udp packet: \(udp)")
            self.logger.trace("UdpProxyConnection.processRemoteData - ipv4 packet: \(ipv4)")

            self.udpLogger.trace("UdpProxyConnection.processRemoteData - udp packet: \(udp)")
            self.udpLogger.trace("UdpProxyConnection.processRemoteData - ipv4 packet: \(ipv4)")
        }

        self.logger.trace("UdpProxyConnection.processRemoteData - writing to client \(ipv4.data.count)")

        // We have a valid UDP packet, so we send it downstream to the client.
        // The client expects raw IPv4 packets prefixed with a 4-byte length.
        try await self.downstream.writeWithLengthPrefix(ipv4.data, 32)

        self.logger.trace("UdpProxyConnection.processRemoteData - wrote to client \(ipv4.data.count)")
        self.udpLogger.info("client <- persona - write \(ipv4.data.count) bytes")
        self.writeLogger.info("\(ipv4.data.count) - \(ipv4.data.hex)")
    }

    // Check if the UDP proxy has timed out.
    // UDP connections never explictly close, so we time them out instead.
    func checkForCleanup(timer: Timer)
    {
        let now = Date()
        let elapsed = now.timeIntervalSince(self.lastUsed)

        self.logger.trace("UdpProxyConnection.checkForCleanup \(now) - \(self.lastUsed) = \(elapsed)/\(UdpProxy.udpTimeout)...")

        if elapsed > UdpProxy.udpTimeout
        {
            self.logger.trace("UdpProxyConnection.checkForCleanup closing connection for \(self.identity.localAddress.string):\(self.identity.localPort)")
            self.udpLogger.trace("UdpProxyConnection.checkForCleanup closing connection for \(self.identity.localAddress.string):\(self.identity.localPort)")

            timer.invalidate()

            UdpProxyConnection.removeConnection(identity: self.identity)
            self.running = false
        }
    }
}
