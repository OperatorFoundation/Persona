//
//  UdpProxy.swift
//  
//
//  Created by Dr. Brandon Wiley on 3/7/22.
//

import Flower
import Foundation
import InternetProtocols
import Net
import Transmission
import Universe

public class UdpProxy
{
    let universe: Universe
    var connections: [UdpProxyConnection] = []

    public init(universe: Universe)
    {
        self.universe = universe
    }

    public func processLocalPacket(_ conduit: Conduit, _ packet: Packet) throws
    {
        guard let ipv4 = packet.ipv4 else
        {
            throw UdpProxyError.notIPv4Packet(packet)
        }

        guard let sourceAddress = IPv4Address(ipv4.sourceAddress) else
        {
            throw UdpProxyError.invalidAddress(ipv4.sourceAddress)
        }

        guard sourceAddress.string == conduit.address else
        {
            throw UdpProxyError.addressMismatch(sourceAddress.string, conduit.address)
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

        if let proxyConnection = self.findConnection(localAddress: sourceAddress, localPort: sourcePort, remoteAddress: destinationAddress, remotePort: destinationPort)
        {
            proxyConnection.processLocalPacket(udp)
        }
        else
        {
            let networkConnection = try self.universe.connect(destinationHost.string, Int(destinationPort), ConnectionType.udp)
            let proxyConnection = self.addConnection(localAddress: sourceAddress, localPort: sourcePort, remoteAddress: destinationAddress, remotePort: destinationPort, conduit: conduit, connection: networkConnection)
            proxyConnection.processLocalPacket(udp)
        }
    }

    func addConnection(localAddress: IPv4Address, localPort: UInt16, remoteAddress: IPv4Address, remotePort: UInt16, conduit: Conduit, connection: Transmission.Connection) -> UdpProxyConnection
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
    let connection: Transmission.Connection

    var lastUsed: Date

    public init(localAddress: IPv4Address, localPort: UInt16, remoteAddress: IPv4Address, remotePort: UInt16, conduit: Conduit, connection: Transmission.Connection)
    {
        self.localAddress = localAddress
        self.localPort = localPort

        self.remoteAddress = remoteAddress
        self.remotePort = remotePort

        self.conduit = conduit
        self.connection = connection

        lastUsed = Date() // now
    }

    func pumpRemote()
    {
        while true
        {
            guard let data = self.connection.read(maxSize: 3000) else
            {
                return
            }

            self.processRemoteData(data)
        }
    }

    public func processLocalPacket(_ udp: UDP)
    {
        guard let payload = udp.payload else
        {
            return
        }

        guard self.connection.write(data: payload) else
        {
            return
        }

        self.lastUsed = Date() // now
    }

    func processRemoteData(_ data: Data)
    {
        // FIXME - add new InternetProtocols constructors
//        let udp = InternetProtocols.UDP(sourcePort: self.remotePort, destinationPort: self.localPort, payload: data)
//        let ipv4 = InternetProtocols.IPv4(sourceAddress: self.remoteAddress, destinationAddress: self.localAddress, payload: udp.data)
//        let message = Message.IPDataV4(ipv4.data)
//        self.conduit.flowerConnection.writeMessage(message: message)

        self.lastUsed = Date() // now
    }
}

public enum UdpProxyError: Error
{
    case addressMismatch(String, String)
    case invalidAddress(Data)
    case notIPv4Packet(Packet)
    case notUdpPacket(Packet)
}
