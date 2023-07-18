//
//  TcpProxy.swift
//
//
//  Created by Dr. Brandon Wiley on 3/7/22.
//

import Logging
import Foundation

import Chord
import Flower
import InternetProtocols
import Net
import Puppy
import Transmission
import Universe

public actor TcpProxy
{
    static let maximumSegmentLifetime = TimeInterval(integerLiteral: 2 * 60) // 2 minutes
    static var quietTimeLock: DispatchSemaphore = DispatchSemaphore(value: 0)
    static var quietTime: Timer? = Timer(timeInterval: TcpProxy.maximumSegmentLifetime, repeats: false)
    {
        timer in

        TcpProxy.quietTime = nil
        TcpProxy.quietTimeLock.signal()
    }

    static public func sequenceLength(_ tcp: InternetProtocols.TCP) -> UInt32
    {
        var length: UInt32 = 0

        if tcp.syn
        {
            length += 1
        }

        if tcp.fin
        {
            length += 1
        }

        if let payload = tcp.payload
        {
            length += UInt32(payload.count)
        }

        return length
    }

    let tcpLogger: Puppy?
    let universe: Universe
    var connections: [TcpProxyConnection] = []

    public init(universe: Universe, quietTime: Bool = true, tcpLogger: Puppy?)
    {
        self.universe = universe
        self.tcpLogger = tcpLogger

        if quietTime
        {
            TcpProxy.quietTimeLock.wait()
        }
    }

    public func processUpstreamPacket(_ conduit: Conduit, _ packet: Packet) throws
    {
        print("\n* Persona.TcpProxy: Attempting to process a TCP packet.")

        guard let ipv4Packet = packet.ipv4 else
        {
            throw TcpProxyError.notIPv4Packet(packet)
        }

        guard let sourceAddress = IPv4Address(ipv4Packet.sourceAddress) else
        {
            throw TcpProxyError.invalidAddress(ipv4Packet.sourceAddress)
        }
        print("* Source Address: \(sourceAddress.string)")

        guard sourceAddress.string == conduit.address else
        {
            throw TcpProxyError.addressMismatch(sourceAddress.string, conduit.address)
        }

        guard let destinationAddress = IPv4Address(ipv4Packet.destinationAddress) else
        {
            throw TcpProxyError.invalidAddress(ipv4Packet.destinationAddress)
        }
        print("* Destination Address: \(destinationAddress)")

        guard let tcp = packet.tcp else
        {
            throw TcpProxyError.notTcpPacket(packet)
        }

        let sourcePort = tcp.sourcePort
        print("* Source Port: \(sourcePort)")

        let destinationPort = tcp.destinationPort
        print("* Destination Port: \(destinationPort)")

        if let proxyConnection = self.findConnection(localAddress: sourceAddress, localPort: sourcePort, remoteAddress: destinationAddress, remotePort: destinationPort, tcp: tcp)
        {
            try proxyConnection.processUpstreamPacket(tcp)
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
            if tcp.destinationPort == 2234
            {
                tcpLogger?.debug("\n************************************************************")
                tcpLogger?.debug("* ⮕ SYN SEQ:\(SequenceNumber(tcp.sequenceNumber)) ❣️")
                tcpLogger?.debug("\n************************************************************")
            }

            // connect() automatically send a syn-ack back for the syn internally
            guard let networkConnection = try? self.universe.connect(destinationAddress.string, Int(destinationPort), ConnectionType.tcp) else
            {
                // Connection failed.
                print("* Persona failed to connect to the destination address \(destinationAddress.string): \(destinationPort)")
                try self.sendRst(sourceAddress: sourceAddress, sourcePort: sourcePort, destinationAddress: destinationAddress, destinationPort: destinationPort, conduit, tcp, .closed)
                return
            }

            do
            {
                try self.addConnection(proxy: self, localAddress: sourceAddress, localPort: sourcePort, remoteAddress: destinationAddress, remotePort: destinationPort, conduit: conduit, connection: networkConnection, irs: SequenceNumber(tcp.sequenceNumber), rcvWnd: tcp.windowSize)

            }
            catch
            {
                print("* Failed to add the connection. Trying sendRst() instead.")

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

    func addConnection(proxy: TcpProxy, localAddress: IPv4Address, localPort: UInt16, remoteAddress: IPv4Address, remotePort: UInt16, conduit: Conduit, connection: Transmission.Connection, irs: SequenceNumber, rcvWnd: UInt16) throws
    {
        do
        {
            let connection = try TcpProxyConnection(proxy: proxy, localAddress: localAddress, localPort: localPort, remoteAddress: remoteAddress, remotePort: remotePort, conduit: conduit, connection: connection, irs: irs, tcpLogger: tcpLogger, rcvWnd: rcvWnd)
            self.connections.append(connection)
        }
        catch
        {
            print("* Failed to initialize a TcpProxyConnection: \(error)")
            throw error
        }
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

    func sendRst(sourceAddress: IPv4Address, sourcePort: UInt16, destinationAddress: IPv4Address, destinationPort: UInt16, _ conduit: Conduit, _ tcp: InternetProtocols.TCP, _ state: States) throws
    {
        print("* Persona sendRst called")
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

                print("* TCP state is closed")

                if tcp.rst
                {
                    print("* received tcp.reset, doing nothing")
                    return
                }
                else if tcp.ack
                {
                    print("* received tcp.ack, calling send packet with sequenceNumber: tcp.acknowledgementNumber, and ack: true")
                    self.tcpLogger?.debug("(proxy)sendRst() called")
                    try self.sendPacket(conduit: conduit, sourceAddress: sourceAddress, sourcePort: sourcePort, destinationAddress: destinationAddress, destinationPort: destinationPort, sequenceNumber: SequenceNumber(tcp.acknowledgementNumber), ack: true)
                }
                else
                {
                    print("* calling send packet with acknowledgement#: tcp.sequenceNumber + TcpProxy.sequenceLength(tcp)")
                    let acknowledgementNumber = SequenceNumber(tcp.sequenceNumber).add(TcpProxy.sequenceLength(tcp))
                    self.tcpLogger?.debug("(proxy)sendRst() called")
                    try self.sendPacket(conduit: conduit, sourceAddress: sourceAddress, sourcePort: sourcePort, destinationAddress: destinationAddress, destinationPort: destinationPort, acknowledgementNumber: acknowledgementNumber)
                }
            case .listen:
                print("* TCP state is listen")
                if tcp.ack
                {
                    /*
                     Any acknowledgment is bad if it arrives on a connection still in
                     the LISTEN state.  An acceptable reset segment should be formed
                     for any arriving ACK-bearing segment.  The RST should be
                     formatted as follows:

                     <SEQ=SEG.ACK><CTL=RST>
                     */

                    print("* received tcp.ack, calling send packet with tcp.acknowledgementNumber, and ack: true")

                    self.tcpLogger?.debug("(proxy)sendRst() called")
                    try self.sendPacket(conduit: conduit, sourceAddress: sourceAddress, sourcePort: sourcePort, destinationAddress: destinationAddress, destinationPort: destinationPort, sequenceNumber: SequenceNumber(tcp.acknowledgementNumber), ack: true)
                }
                else
                {
                    print("* no tcp.ack received, doing nothing")
                    return
                }

            default:
                print("* TCP state is an unexpected value, doing nothing")
                return
        }
    }

    func sendPacket(conduit: Conduit, sourceAddress: IPv4Address, sourcePort: UInt16, destinationAddress: IPv4Address, destinationPort: UInt16, sequenceNumber: SequenceNumber = SequenceNumber(0), acknowledgementNumber: SequenceNumber = SequenceNumber(0), ack: Bool = false) throws
    {
        guard let ipv4 = try? IPv4(sourceAddress: sourceAddress, destinationAddress: destinationAddress, sourcePort: sourcePort, destinationPort: destinationPort, sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, syn: false, ack: ack, fin: false, rst: true, windowSize: 0, payload: nil) else
        {
            print("* sendPacket() failed to create an IPV4packet")
            throw TcpProxyError.badIpv4Packet
        }

        let message = Message.IPDataV4(ipv4.data)

        print("* Created an IPDataV4 message, asking flower to write the message...")
        conduit.flowerConnection.writeMessage(message: message)
    }
}
