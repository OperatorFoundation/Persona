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

    public init(universe: Universe)
    {
        self.universe = universe
    }

    public func processLocalPacket(_ conduit: Conduit, _ packet: Packet) throws
    {
        guard let ipv4 = packet.ipv4 else
        {
            throw TcpProxyError.notIPv4Packet(packet)
        }

        guard let sourceAddress = IPv4Address(ipv4.sourceAddress) else
        {
            throw TcpProxyError.invalidAddress(ipv4.sourceAddress)
        }

        guard sourceAddress.string == conduit.address else
        {
            throw TcpProxyError.addressMismatch(sourceAddress.string, conduit.address)
        }

        guard let destinationAddress = IPv4Address(ipv4.destinationAddress) else
        {
            throw TcpProxyError.invalidAddress(ipv4.destinationAddress)
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
            guard let networkConnection = try? self.universe.connect(destinationAddress.string, Int(destinationPort), ConnectionType.tcp) else
            {
                // Connection failed.

                try self.sendRst(sourceAddress: sourceAddress, sourcePort: sourcePort, destinationAddress: destinationAddress, destinationPort: destinationPort, conduit, tcp, .closed)
                return
            }

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
        let connection = try TcpProxyConnection(proxy: proxy, localAddress: localAddress, localPort: localPort, remoteAddress: remoteAddress, remotePort: remotePort, conduit: conduit, connection: connection, irs: irs)
        self.connections.append(connection)
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
                    let ack = try InternetProtocols.TCP(sourcePort: sourcePort, destinationPort: destinationPort, sequenceNumber: SequenceNumber(tcp.acknowledgementNumber), rst: true)
                    let packet = try IPv4(sourceAddress: sourceAddress, destinationAddress: destinationAddress, tcp: ack)
                    let message = Message.IPDataV4(packet.data)
                    conduit.flowerConnection.writeMessage(message: message)
                }
                else
                {
                    let ack = try InternetProtocols.TCP(sourcePort: sourcePort, destinationPort: destinationPort, sequenceNumber: SequenceNumber(0), acknowledgementNumber: SequenceNumber(tcp.sequenceNumber).add(TransmissionControlBlock.sequenceLength(tcp)), ack: true, rst: true)
                    let packet = try IPv4(sourceAddress: sourceAddress, destinationAddress: destinationAddress, tcp: ack)
                    let message = Message.IPDataV4(packet.data)
                    conduit.flowerConnection.writeMessage(message: message)
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

                    let ack = try InternetProtocols.TCP(sourcePort: sourcePort, destinationPort: destinationPort, sequenceNumber: SequenceNumber(tcp.acknowledgementNumber), rst: true)
                    let packet = try IPv4(sourceAddress: sourceAddress, destinationAddress: destinationAddress, tcp: ack)
                    let message = Message.IPDataV4(packet.data)
                    conduit.flowerConnection.writeMessage(message: message)
                }
                else
                {
                    return
                }

            default:
                return
        }
    }
}

class TcpProxyConnection: Equatable
{
    static public func ==(_ x: TcpProxyConnection, _ y: TcpProxyConnection) -> Bool
    {
        if x.localAddress != y.localAddress {return false}
        if x.localPort != y.localPort {return false}
        if x.remoteAddress != y.remoteAddress {return false}
        if x.remotePort != y.remotePort {return false}

        return true
    }

    let proxy: TcpProxy
    let localAddress: IPv4Address
    let localPort: UInt16

    let remoteAddress: IPv4Address
    let remotePort: UInt16

    let conduit: Conduit
    let connection: Transmission.Connection

    var lastUsed: Date

    var open: Bool = true

    var state: TCP.States
    var vars: TcpStateVariables
    var retransmissionQueue: [InternetProtocols.TCP] = []

    public init(proxy: TcpProxy, localAddress: IPv4Address, localPort: UInt16, remoteAddress: IPv4Address, remotePort: UInt16, conduit: Conduit, connection: Transmission.Connection, irs: SequenceNumber) throws
    {
        self.proxy = proxy
        self.localAddress = localAddress
        self.localPort = localPort

        self.remoteAddress = remoteAddress
        self.remotePort = remotePort

        self.conduit = conduit
        self.connection = connection

        self.lastUsed = Date() // now

        self.state = .synReceived
        self.vars = try TcpStateVariables(segSeq: irs)
        try self.sendSynAck(conduit)
    }

    public func processLocalPacket(_ tcp: InternetProtocols.TCP) throws
    {
        if self.inWindow(tcp)
        {
            if tcp.rst
            {
                /*
                 SYN-RECEIVED STATE

                 If the RST bit is set

                 If this connection was initiated with a passive OPEN (i.e.,
                 came from the LISTEN state), then return this connection to
                 LISTEN state and return.  The user need not be informed.  If
                 this connection was initiated with an active OPEN (i.e., came
                 from SYN-SENT state) then the connection was refused, signal
                 the user "connection refused".  In either case, all segments
                 on the retransmission queue should be removed.  And in the
                 active OPEN case, enter the CLOSED state and delete the TCB,
                 and return.
                 */
                self.close()
            }
            else if tcp.syn
            {
                /*
                 If the SYN is in the window it is an error, send a reset, any
                 outstanding RECEIVEs and SEND should receive "reset" responses,
                 all segment queues should be flushed, the user should also
                 receive an unsolicited general "connection reset" signal, enter
                 the CLOSED state, delete the TCB, and return.
                 */

                try self.sendRst(self.conduit, tcp, .closed)
                self.close()
            }
            else if tcp.ack
            {
                switch state
                {
                    case .synReceived:
                        /*
                         SYN-RECEIVED STATE

                         If SND.UNA =< SEG.ACK =< SND.NXT then enter ESTABLISHED state
                         and continue processing.

                         If the segment acknowledgment is not acceptable, form a
                         reset segment,

                         <SEQ=SEG.ACK><CTL=RST>

                         and send it.
                         */

                        if (self.vars.sndUna <= SequenceNumber(tcp.acknowledgementNumber)) && (SequenceNumber(tcp.acknowledgementNumber) <= self.vars.sndNxt)
                        {
                            self.state = .established
                        }
                        else
                        {
                            try self.sendRst(self.conduit, tcp, self.state)
                        }

                    case .established, .finWait1, .finWait2, .closeWait, .closing, .lastAck, .timeWait:
                        /*
                         ESTABLISHED STATE
                         */

                        /*
                         Note that SND.WND is an offset from SND.UNA, that SND.WL1
                         records the sequence number of the last segment used to update
                         SND.WND, and that SND.WL2 records the acknowledgment number of
                         the last segment used to update SND.WND.  The check here
                         prevents using old segments to update the window.
                         */

                        /*
                         If SND.UNA < SEG.ACK =< SND.NXT then,
                         */
                        if (self.vars.sndUna < SequenceNumber(tcp.acknowledgementNumber)) && (SequenceNumber(tcp.acknowledgementNumber) <= self.vars.sndNxt)
                        {
                            /*
                             set SND.UNA <- SEG.ACK.
                             */
                            self.vars.sndUna = SequenceNumber(tcp.acknowledgementNumber)

                            /*
                             Any segments on the retransmission queue which are thereby
                             entirely acknowledged are removed.
                             */
                            self.filterRetransmissions(SequenceNumber(tcp.acknowledgementNumber))

                            /*
                             If SND.UNA < SEG.ACK =< SND.NXT, the send window should be updated.
                             If (SND.WL1 < SEG.SEQ or
                                (SND.WL1 = SEG.SEQ and SND.WL2 =< SEG.ACK)),
                             */
                            if  (self.vars.sndWl1 <  SequenceNumber(tcp.sequenceNumber)) ||
                               ((self.vars.sndWl1 == SequenceNumber(tcp.sequenceNumber)) && (self.vars.sndWl2 <= SequenceNumber(tcp.acknowledgementNumber)))
                            {
                                /*
                                 set SND.WND <- SEG.WND,
                                 */
                                let segWnd = SequenceNumber(tcp.sequenceNumber).add(TransmissionControlBlock.sequenceLength(tcp))
                                self.vars.sndWnd = segWnd

                                /*
                                 set SND.WL1 <- SEG.SEQ,
                                 */
                                self.vars.sndWl1 = tcp.sequenceNumber

                                /*
                                 and set SND.WL2 <- SEG.ACK.
                                 */
                                self.vars.sndWl2 = tcp.acknowledgementNumber
                            }
                        }
                        else if SequenceNumber(tcp.acknowledgementNumber) < self.vars.sndUna
                        {
                            /*
                             If the ACK is a duplicate (SEG.ACK < SND.UNA), it can be ignored.
                             */
                            return
                        }
                        else if SequenceNumber(tcp.acknowledgementNumber) > self.vars.sndNxt
                        {
                            /*
                             If the ACK acks something not yet sent (SEG.ACK > SND.NXT) then send an ACK, drop the segment, and return.
                             */
                            return
                        }

                        // Additional processing for specific states
                        switch state
                        {
                            case .finWait1:
                                /*
                                 FIN-WAIT-1 STATE

                                 In addition to the processing for the ESTABLISHED state, if
                                 our FIN is now acknowledged then enter FIN-WAIT-2 and continue
                                 processing in that state.
                                 */
                                if self.retransmissionQueue.isEmpty
                                {
                                    self.state = .finWait2
                                    return
                                }

                            case .finWait2:
                                /*
                                 FIN-WAIT-2 STATE

                                 In addition to the processing for the ESTABLISHED state, if
                                 the retransmission queue is empty, the user's CLOSE can be
                                 acknowledged ("ok") but do not delete the TCB.
                                 */

                                // Nothing for us to do here in our implementation.
                                return

                            case .closeWait:
                                /*
                                 CLOSE-WAIT STATE

                                 Do the same processing as for the ESTABLISHED state.
                                 */

                                return

                            case .closing:
                                /*
                                 CLOSING STATE

                                 In addition to the processing for the ESTABLISHED state, if
                                 the ACK acknowledges our FIN then enter the TIME-WAIT state,
                                 otherwise ignore the segment.
                                 */

                                if self.retransmissionQueue.isEmpty
                                {
                                    self.state = .timeWait
                                    return
                                }

                            case .lastAck:
                                /*
                                 LAST-ACK STATE

                                 The only thing that can arrive in this state is an
                                 acknowledgment of our FIN.  If our FIN is now acknowledged,
                                 delete the TCB, enter the CLOSED state, and return.
                                 */

                                if self.retransmissionQueue.isEmpty
                                {
                                    self.close()
                                }

                            default:
                                return
                        }

                    default:
                        return
                }
            }
            else
            {
                /*
                 if the ACK bit is off drop the segment and return
                 */

                return
            }
        }
        else
        {
            /*
             If an incoming segment is not acceptable, an acknowledgment
             should be sent in reply (unless the RST bit is set, if so drop
             the segment and return):

             <SEQ=SND.NXT><ACK=RCV.NXT><CTL=ACK>

             After sending the acknowledgment, drop the unacceptable segment
             and return.
             */

            if tcp.rst
            {
                return
            }
            else
            {
                let ack = InternetProtocols.TCP(sourcePort: self.remotePort, destinationPort: self.localPort, sequenceNumber: self.vars.sndNxt, acknowledgementNumber: self.vars.rcvNxt, ack: true)
                let packet = try IPv4(sourceAddress: self.remoteAddress, destinationAddress: self.localAddress, tcp: ack)
                let message = Message.IPDataV4(packet.data)
                conduit.flowerConnection.writeMessage(message: message)
            }
        }

        if tcp.rst
        {
            self.close()
            self.sendAck(tcp, .closed)
        }
        else
        {
            guard let payload = tcp.payload else
            {
                return
            }

            guard self.connection.write(data: payload) else
            {
                return
            }

            self.lastUsed = Date() // now
        }
    }

    public func close()
    {
        self.open = false
        self.connection.close()
        self.proxy.removeConnection(self)
    }

    func filterRetransmissions(_ ack: SequenceNumber)
    {
        self.retransmissionQueue = self.retransmissionQueue.filter
        {
            (tcp: InternetProtocols.TCP) -> Bool in

            let expectedAck = SequenceNumber(tcp.sequenceNumber).add(Int(TransmissionControlBlock.sequenceLength(tcp)))
            return ack < expectedAck // Keep packets which have not been acked
        }
    }

    func inWindow(_ tcp: InternetProtocols.TCP) -> Bool
    {
        let rcvLast = self.vars.rcvNxt.add(Int(self.vars.rcvWnd))
        let segSeq = SequenceNumber(tcp.sequenceNumber)
        let segLen = TransmissionControlBlock.sequenceLength(tcp)
        let segLast = segSeq.add(segLen - 1)

        if segLen == 0
        {
            if self.vars.rcvWnd == 0
            {
                return segSeq == self.vars.rcvNxt
            }
            else // rcvWnd > 0
            {
                return (self.vars.rcvNxt <= segSeq) && (segSeq < rcvLast)
            }
        }
        else // seqLen > 0
        {
            if self.vars.rcvWnd == 0
            {
                return false
            }
            else // rcvWnd > 0
            {
                return (self.vars.rcvNxt <=  segSeq) && (segSeq  < rcvLast) ||
                (self.vars.rcvNxt <= segLast) && (segLast < rcvLast)
            }
        }
    }

    func pumpRemote()
    {
        while self.open
        {
            guard let data = self.connection.read(maxSize: 3000) else
            {
                // Remote side closed connection
                self.close()
                return
            }

            self.processRemoteData(data)
        }
    }

    func processRemoteData(_ data: Data)
    {
        // FIXME - add new InternetProtocols constructors
        //        let tcp = InternetProtocols.TCP(sourcePort: self.remotePort, destinationPort: self.localPort, payload: data)
        //        let ipv4 = InternetProtocols.IPv4(sourceAddress: self.remoteAddress, destinationAddress: self.localAddress, payload: tcp.data)
        //        let message = Message.IPDataV4(ipv4.data)
        //        self.conduit.flowerConnection.writeMessage(message: message)

        self.lastUsed = Date() // now
    }

    func sendSynAck(_ conduit: Conduit) throws
    {
        let synAck = try InternetProtocols.TCP(sourcePort: self.remotePort, destinationPort: self.localPort, sequenceNumber: self.vars.iss, acknowledgementNumber: self.vars.rcvNxt, syn: true, ack: true)
        let packet = try IPv4(sourceAddress: self.remoteAddress, destinationAddress: self.localAddress, tcp: synAck)
        let message = Message.IPDataV4(packet.data)
        conduit.flowerConnection.writeMessage(message: message)
    }

    func sendAck(_ tcp: InternetProtocols.TCP, _ state: TCP.States)
    {

    }

    func sendRst(_ conduit: Conduit, _ tcp: InternetProtocols.TCP, _ state: TCP.States) throws
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
                    let ack = try InternetProtocols.TCP(sourcePort: self.remotePort, destinationPort: self.localPort, sequenceNumber: SequenceNumber(tcp.acknowledgementNumber), rst: true)
                    let packet = try IPv4(sourceAddress: self.remoteAddress, destinationAddress: self.localAddress, tcp: ack)
                    let message = Message.IPDataV4(packet.data)
                    conduit.flowerConnection.writeMessage(message: message)
                }
                else
                {
                    let ack = try InternetProtocols.TCP(sourcePort: self.remotePort, destinationPort: self.localPort, sequenceNumber: SequenceNumber(0), acknowledgementNumber: SequenceNumber(tcp.sequenceNumber).add(TransmissionControlBlock.sequenceLength(tcp)), ack: true, rst: true)
                    let packet = try IPv4(sourceAddress: self.remoteAddress, destinationAddress: self.localAddress, tcp: ack)
                    let message = Message.IPDataV4(packet.data)
                    conduit.flowerConnection.writeMessage(message: message)
                }

            case .synReceived:
                /*
                 If the segment acknowledgment is not acceptable, form a
                 reset segment,

                 <SEQ=SEG.ACK><CTL=RST>

                 and send it.
                 */

                let ack = try InternetProtocols.TCP(sourcePort: self.remotePort, destinationPort: self.localPort, sequenceNumber: SequenceNumber(tcp.acknowledgementNumber), rst: true)
                let packet = try IPv4(sourceAddress: self.remoteAddress, destinationAddress: self.localAddress, tcp: ack)
                let message = Message.IPDataV4(packet.data)
                conduit.flowerConnection.writeMessage(message: message)

            default:
                return // FIXME
        }
    }

}

public class TcpStateVariables
{
    var irs: SequenceNumber
    var rcvNxt: SequenceNumber
    var iss: SequenceNumber
    var sndUna: SequenceNumber
    var sndNxt: SequenceNumber

    // SYN-RECEIVED
    public init(segSeq: SequenceNumber) throws
    {
        self.irs = segSeq
        self.rcvNxt = segSeq.increment()
        self.iss = try isn()
        self.sndNxt = self.iss.increment()
        self.sndUna = self.iss
    }
}

public enum TcpProxyError: Error
{
    case addressMismatch(String, String)
    case invalidAddress(Data)
    case notIPv4Packet(Packet)
    case notTcpPacket(Packet)
}
