//
//  UdpProxy.swift
//
//
//  Created by Dr. Brandon Wiley on 3/7/22.
//

import Foundation

import InternetProtocols
import Net
import TransmissionAsync

public class UdpProxy
{
    let client: AsyncConnection
    var connections: [UdpProxyConnection] = []

    public init(client: AsyncConnection)
    {
        self.client = client
    }

    public func processLocalPacket(_ packet: Packet) throws
    {
//        guard let ipv4 = packet.ipv4 else
//        {
//            throw UdpProxyError.notIPv4Packet(packet)
//        }
//
//        guard let sourceAddress = IPv4Address(ipv4.sourceAddress) else
//        {
//            throw UdpProxyError.invalidAddress(ipv4.sourceAddress)
//        }
//
//        guard sourceAddress.string == conduit.address else
//        {
//            throw UdpProxyError.addressMismatch(sourceAddress.string, conduit.address)
//        }
//
//        guard let destinationAddress = IPv4Address(ipv4.destinationAddress) else
//        {
//            throw UdpProxyError.invalidAddress(ipv4.destinationAddress)
//        }
//
//        guard let destinationHost = NWEndpoint.Host(data: ipv4.destinationAddress) else
//        {
//            throw UdpProxyError.invalidAddress(ipv4.destinationAddress)
//
//        }
//
//        guard let udp = packet.udp else
//        {
//            throw UdpProxyError.notUdpPacket(packet)
//        }
//
//        let sourcePort = udp.sourcePort
//        let destinationPort = udp.destinationPort
//
//        if let proxyConnection = self.findConnection(localAddress: sourceAddress, localPort: sourcePort, remoteAddress: destinationAddress, remotePort: destinationPort)
//        {
//            proxyConnection.processLocalPacket(udp)
//        }
//        else
//        {
//            let networkConnection =
//            try self.universe.connect(destinationHost.string, Int(destinationPort), ConnectionType.udp)
//            let proxyConnection = self.addConnection(localAddress: sourceAddress, localPort: sourcePort, remoteAddress: destinationAddress, remotePort: destinationPort, conduit: conduit, connection: networkConnection)
//            proxyConnection.processLocalPacket(udp)
//        }
    }

    func addConnection(localAddress: IPv4Address, localPort: UInt16, remoteAddress: IPv4Address, remotePort: UInt16, conduit: Conduit, connection: AsyncConnection) -> UdpProxyConnection
    {
        let connection = UdpProxyConnection(localAddress: localAddress, localPort: localPort, remoteAddress: remoteAddress, remotePort: remotePort, conduit: conduit, connection: connection)
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
    let localAddress: IPv4Address
    let localPort: UInt16

    let remoteAddress: IPv4Address
    let remotePort: UInt16

    let conduit: Conduit
    let connection: AsyncConnection

    var lastUsed: Date
    let queue = DispatchQueue(label: "UdpProxyConnection")

    public init(localAddress: IPv4Address, localPort: UInt16, remoteAddress: IPv4Address, remotePort: UInt16, conduit: Conduit, connection: AsyncConnection)
    {
        self.localAddress = localAddress
        self.localPort = localPort

        self.remoteAddress = remoteAddress
        self.remotePort = remotePort

        self.conduit = conduit
        self.connection = connection

        lastUsed = Date() // now

        self.queue.async
        {
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
    }

    func pumpRemote() async throws
    {
        while true
        {
            let data = try await self.connection.readMaxSize(3000)
            self.processRemoteData(data)
        }
    }

    public func processLocalPacket(_ udp: UDP) async throws
    {
        guard let payload = udp.payload else
        {
            return
        }

        try await self.connection.write(payload)
        self.lastUsed = Date() // now
    }

    func processRemoteData(_ data: Data)
    {
//        guard let udp = InternetProtocols.UDP(sourcePort: self.remotePort, destinationPort: self.localPort, payload: data) else
//        {
//            return
//        }
//
//        do
//        {
//            guard let ipv4 = try InternetProtocols.IPv4(sourceAddress: self.remoteAddress, destinationAddress: self.localAddress, payload: udp.data, protocolNumber: InternetProtocols.IPprotocolNumber.UDP) else
//            {
//                return
//            }
//
//            let message = Message.IPDataV4(ipv4.data)
//            self.conduit.flowerConnection.writeMessage(message: message)
//
//            self.lastUsed = Date() // now
//        }
//        catch
//        {
//            return
//        }
    }
}

public enum UdpProxyError: Error
{
    case addressMismatch(String, String)
    case invalidAddress(Data)
    case notIPv4Packet(Packet)
    case notUdpPacket(Packet)
}
