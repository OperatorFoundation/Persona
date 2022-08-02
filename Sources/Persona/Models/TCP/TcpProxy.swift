//
//  TcpProxy.swift
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

public class TcpProxy
{
    let universe: Universe
    var connections: [TcpProxyConnection] = []

    public init(universe: Universe, quietTime: Bool = true)
    {
        self.universe = universe

        if quietTime
        {
            TCP.quietTimeLock.wait()
        }
    }

    public func processLocalPacket(_ conduit: Conduit, _ packet: Packet) throws
    {
        guard let ipv4Packet = packet.ipv4 else
        {
            throw TcpProxyError.notIPv4Packet(packet)
        }

        guard let sourceAddress = IPv4Address(ipv4Packet.sourceAddress) else
        {
            throw TcpProxyError.invalidAddress(ipv4Packet.sourceAddress)
        }

        guard sourceAddress.string == conduit.address else
        {
            throw TcpProxyError.addressMismatch(sourceAddress.string, conduit.address)
        }

        guard let destinationAddress = IPv4Address(ipv4Packet.destinationAddress) else
        {
            throw TcpProxyError.invalidAddress(ipv4Packet.destinationAddress)
        }

        guard let tcp = packet.tcp else
        {
            throw TcpProxyError.notTcpPacket(packet)
        }

        let sourcePort = tcp.sourcePort
        let destinationPort = tcp.destinationPort

        if let proxyConnection = self.findConnection(localAddress: sourceAddress, localPort: sourcePort, remoteAddress: destinationAddress, remotePort: destinationPort, tcp: tcp)
        {
            try proxyConnection.processLocalPacket(tcp)
        }
        else
        {
            try self.handleNewConnection(tcp: tcp, sourceAddress: sourceAddress, sourcePort: sourcePort, destinationAddress: destinationAddress, destinationPort: destinationPort, conduit: conduit)
        }
    }

    func handleNewConnection(tcp: InternetProtocols.TCP, sourceAddress: IPv4Address, sourcePort: UInt16, destinationAddress: IPv4Address, destinationPort: UInt16, conduit: Conduit) throws
    {
        // When we receive a packet bound for a new destination,
        // if we can connect to that destination,
        //      we respond as if we are in the LISTEN state
        // otherwise,
        //      we respond as if we are in the CLOSED state

        if tcp.rst
        {
            /*
             If the state is LISTEN then

             first check for an RST

             An incoming RST should be ignored.  Return.
             */

            return
        }
        else if tcp.ack
        {
            /*
             second check for an ACK

             Any acknowledgment is bad if it arrives on a connection still in
             the LISTEN state.  An acceptable reset segment should be formed
             for any arriving ACK-bearing segment.  The RST should be
             formatted as follows:

             <SEQ=SEG.ACK><CTL=RST>

             Return.
             */

            try self.sendRst(sourceAddress: sourceAddress, sourcePort: sourcePort, destinationAddress: destinationAddress, destinationPort: destinationPort, conduit, tcp, .listen)
            return
        }
        else if tcp.syn // A new connection requires a SYN packet
        {
            // connect() automatically send a syn-ack back for the syn internally
            guard let networkConnection = try? self.universe.connect(destinationAddress.string, Int(destinationPort), ConnectionType.tcp) else
            {
                // Connection failed.

                try self.sendRst(sourceAddress: sourceAddress, sourcePort: sourcePort, destinationAddress: destinationAddress, destinationPort: destinationPort, conduit, tcp, .closed)
                return
            }
            
            print(" * Persona connected to the destination server (tcp.syn).")
            do
            {
                try self.addConnection(proxy: self, localAddress: sourceAddress, localPort: sourcePort, remoteAddress: destinationAddress, remotePort: destinationPort, conduit: conduit, connection: networkConnection, irs: SequenceNumber(tcp.sequenceNumber))
                
            }
            catch
            {
                try self.sendRst(sourceAddress: sourceAddress, sourcePort: sourcePort, destinationAddress: destinationAddress, destinationPort: destinationPort, conduit, tcp, .closed)
                return
            }
        }
        else
        {
            /*
             Any other control or text-bearing segment (not containing SYN)
             must have an ACK and thus would be discarded by the ACK
             processing.  An incoming RST segment could not be valid, since
             it could not have been sent in response to anything sent by this
             incarnation of the connection.  So you are unlikely to get here,
             but if you do, drop the segment, and return.
             */
        }
    }

    func addConnection(proxy: TcpProxy, localAddress: IPv4Address, localPort: UInt16, remoteAddress: IPv4Address, remotePort: UInt16, conduit: Conduit, connection: Transmission.Connection, irs: SequenceNumber) throws
    {
        print(" * Making a TcpProxyConnection")
        let connection = try TcpProxyConnection(proxy: proxy, localAddress: localAddress, localPort: localPort, remoteAddress: remoteAddress, remotePort: remotePort, conduit: conduit, connection: connection, irs: irs)
        self.connections.append(connection)
        print(" * Created a TcpProxyConnection")
    }

    func findConnection(localAddress: IPv4Address, localPort: UInt16, remoteAddress: IPv4Address, remotePort: UInt16, tcp: InternetProtocols.TCP) -> TcpProxyConnection?
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

    func removeConnection(_ connection: TcpProxyConnection)
    {
        self.connections.removeAll
        {
            item in

            item == connection
        }
    }

    func sendRst(sourceAddress: IPv4Address, sourcePort: UInt16, destinationAddress: IPv4Address, destinationPort: UInt16, _ conduit: Conduit, _ tcp: InternetProtocols.TCP, _ state: TCP.States) throws
    {
        switch state
        {
            case .closed:
                /*
                 If the state is CLOSED (i.e., TCB does not exist) then

                 all data in the incoming segment is discarded.  An incoming
                 segment containing a RST is discarded.  An incoming segment not
                 containing a RST causes a RST to be sent in response.  The
                 acknowledgment and sequence field values are selected to make the
                 reset sequence acceptable to the TCP that sent the offending
                 segment.

                 If the ACK bit is off, sequence number zero is used,

                 <SEQ=0><ACK=SEG.SEQ+SEG.LEN><CTL=RST,ACK>

                 If the ACK bit is on,

                 <SEQ=SEG.ACK><CTL=RST>

                 Return.
                 */

                if tcp.rst
                {
                    return
                }
                else if tcp.ack
                {
                    try self.sendPacket(conduit: conduit, sourceAddress: sourceAddress, sourcePort: sourcePort, destinationAddress: destinationAddress, destinationPort: destinationPort, sequenceNumber: SequenceNumber(tcp.acknowledgementNumber))
                }
                else
                {
                    let acknowledgementNumber = SequenceNumber(tcp.sequenceNumber).add(TransmissionControlBlock.sequenceLength(tcp))
                    try self.sendPacket(conduit: conduit, sourceAddress: sourceAddress, sourcePort: sourcePort, destinationAddress: destinationAddress, destinationPort: destinationPort, acknowledgementNumber: acknowledgementNumber, ack: true)
                }
            case .listen:
                if tcp.ack
                {
                    /*
                     Any acknowledgment is bad if it arrives on a connection still in
                     the LISTEN state.  An acceptable reset segment should be formed
                     for any arriving ACK-bearing segment.  The RST should be
                     formatted as follows:

                     <SEQ=SEG.ACK><CTL=RST>
                     */

                    try self.sendPacket(conduit: conduit, sourceAddress: sourceAddress, sourcePort: sourcePort, destinationAddress: destinationAddress, destinationPort: destinationPort, sequenceNumber: SequenceNumber(tcp.acknowledgementNumber), ack: true)
                }
                else
                {
                    return
                }

            default:
                return
        }
    }

    func sendPacket(conduit: Conduit, sourceAddress: IPv4Address, sourcePort: UInt16, destinationAddress: IPv4Address, destinationPort: UInt16, sequenceNumber: SequenceNumber = SequenceNumber(0), acknowledgementNumber: SequenceNumber = SequenceNumber(0), ack: Bool = false) throws
    {
        guard let ipv4 = try IPv4(sourceAddress: sourceAddress, destinationAddress: destinationAddress, sourcePort: sourcePort, destinationPort: destinationPort, sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, syn: false, ack: ack, fin: false, rst: true, windowSize: 0, payload: nil) else
        {
            throw TcpProxyError.badIpv4Packet
        }

        let message = Message.IPDataV4(ipv4.data)
        conduit.flowerConnection.writeMessage(message: message)
    }
}
