//
//  UdpProxy.swift
//
//
//  Created by Dr. Brandon Wiley on 3/7/22.
//

import Logging
import Foundation

import InternetProtocols
import Net
import TransmissionAsync

public class UdpProxy
{
    let client: AsyncConnection
    var connections: [UdpProxyConnection] = []
    let logger: Logger

    public init(client: AsyncConnection, logger: Logger)
    {
        self.client = client
        self.logger = logger
    }

    public func processLocalPacket(_ packet: Packet) async throws
    {
        self.logger.trace("processLocalPacket(\(packet.rawBytes.count))")

        guard let ipv4 = packet.ipv4 else
        {
            throw UdpProxyError.notIPv4Packet(packet)
        }

        guard let sourceAddress = IPv4Address(ipv4.sourceAddress) else
        {
            throw UdpProxyError.invalidAddress(ipv4.sourceAddress)
        }

        guard let destinationAddress = IPv4Address(ipv4.destinationAddress) else
        {
            throw UdpProxyError.invalidAddress(ipv4.destinationAddress)
        }

        guard let destinationHost = NWEndpoint.Host(data: ipv4.destinationAddress) else
        {
            throw UdpProxyError.invalidAddress(ipv4.destinationAddress)
        }

        guard let udp = packet.udp else
        {
            throw UdpProxyError.notUdpPacket(packet)
        }

        let sourcePort = udp.sourcePort
        let destinationPort = udp.destinationPort

        self.logger.debug("processing local packet \(sourceAddress):\(sourcePort) -> \(destinationAddress):\(destinationPort)")

        if let proxyConnection = self.findConnection(localAddress: sourceAddress, localPort: sourcePort, remoteAddress: destinationAddress, remotePort: destinationPort)
        {
            try await proxyConnection.processLocalPacket(destinationHost, destinationPort, udp)
        }
        else
        {
            let networkConnection = try await AsyncTcpSocketConnection("127.0.0.1", 1233, self.logger)
            let proxyConnection = self.addConnection(localAddress: sourceAddress, localPort: sourcePort, remoteAddress: destinationAddress, remotePort: destinationPort, connection: networkConnection)
            try await proxyConnection.processLocalPacket(destinationHost, destinationPort, udp)
        }
    }

    func addConnection(localAddress: IPv4Address, localPort: UInt16, remoteAddress: IPv4Address, remotePort: UInt16, connection: AsyncConnection) -> UdpProxyConnection
    {
        let connection = UdpProxyConnection(client: self.client, localAddress: localAddress, localPort: localPort, remoteAddress: remoteAddress, remotePort: remotePort, connection: connection, logger: self.logger)
        self.connections.append(connection)
        return connection
    }

    func findConnection(localAddress: IPv4Address, localPort: UInt16, remoteAddress: IPv4Address, remotePort: UInt16) -> UdpProxyConnection?
    {
        return self.connections.first
        {
            connection in

            return (connection.localAddress  == localAddress ) &&
            (connection.localPort     == localPort    ) &&
            (connection.remoteAddress == remoteAddress) &&
            (connection.remotePort    == remotePort   )
        }
    }
}

class UdpProxyConnection
{
    let client: AsyncConnection
    let localAddress: IPv4Address
    let localPort: UInt16

    let remoteAddress: IPv4Address
    let remotePort: UInt16

    let connection: AsyncConnection

    var lastUsed: Date
    let queue = DispatchQueue(label: "UdpProxyConnection")
    let logger: Logger

    public init(client: AsyncConnection, localAddress: IPv4Address, localPort: UInt16, remoteAddress: IPv4Address, remotePort: UInt16, connection: AsyncConnection, logger: Logger)
    {
        self.client = client
        self.localAddress = localAddress
        self.localPort = localPort

        self.remoteAddress = remoteAddress
        self.remotePort = remotePort

        self.connection = connection

        self.logger = logger

        lastUsed = Date() // now

        Task
        {
            do
            {
                try await self.pumpRemote()
            }
            catch
            {
                return
            }
        }
    }

    func pumpRemote() async throws
    {
        self.logger.debug("UdpProxConnection.pumpRemote()")
        while true
        {
            self.logger.debug("UdpProxConnection.pumpRemote() - readMaxSize(3000)")
            let data = try await self.connection.readWithLengthPrefix(prefixSizeInBits: 32)
            self.logger.debug("UdpProxConnection.pumpRemote() - read \(data.count)")
            try await self.processRemoteData(data)
        }
    }

    public func processLocalPacket(_ destinationHost: NWEndpoint.Host, _ destinationPort: UInt16, _ udp: UDP) async throws
    {
        let destinationBytes = destinationHost.data + destinationPort.maybeNetworkData!
        guard let payload = udp.payload else
        {
            return
        }

        let bytes = destinationBytes + payload
        
        print("Writing \(bytes.count) bytes to the UDP Proxy Server:")
        print(bytes.hex)
        
        try await self.connection.writeWithLengthPrefix(bytes, 32)
        self.lastUsed = Date() // now
    }

    func processRemoteData(_ data: Data) async throws
    {
        guard let udp = InternetProtocols.UDP(sourcePort: self.remotePort, destinationPort: self.localPort, payload: data) else
        {
            return
        }

        do
        {
            guard let ipv4 = try InternetProtocols.IPv4(sourceAddress: self.remoteAddress, destinationAddress: self.localAddress, payload: udp.data, protocolNumber: InternetProtocols.IPprotocolNumber.UDP) else
            {
                return
            }

            try await self.client.writeWithLengthPrefix(ipv4.data, 32)
            self.lastUsed = Date() // now
        }
        catch
        {
            return
        }
    }
}

public enum UdpProxyError: Error
{
    case addressMismatch(String, String)
    case invalidAddress(Data)
    case notIPv4Packet(Packet)
    case notUdpPacket(Packet)
}
