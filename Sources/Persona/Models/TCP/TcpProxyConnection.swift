//
//  TcpProxyConnection.swift
//  
//
//  Created by Dr. Brandon Wiley on 3/11/22.
//
import Logging

import Chord
import Flower
import Foundation
import InternetProtocols
import Net
import Puppy
import Transmission

public class TcpProxyConnection: Equatable
{
    static public func ==(_ x: TcpProxyConnection, _ y: TcpProxyConnection) -> Bool
    {
        if x.localAddress != y.localAddress {return false}
        if x.localPort != y.localPort {return false}
        if x.remoteAddress != y.remoteAddress {return false}
        if x.remotePort != y.remotePort {return false}

        return true
    }

    // Initial sequence number generator - Section 3.3, page 27
    /*
     To avoid confusion we must prevent segments from one incarnation of a
     connection from being used while the same sequence numbers may still
     be present in the network from an earlier incarnation.  We want to
     assure this, even if a TCP crashes and loses all knowledge of the
     sequence numbers it has been using.  When new connections are created,
     an initial sequence number (ISN) generator is employed which selects a
     new 32 bit ISN.  The generator is bound to a (possibly fictitious) 32
     bit clock whose low order bit is incremented roughly every 4
     microseconds.  Thus, the ISN cycles approximately every 4.55 hours.
     Since we assume that segments will stay in the network no more than
     the Maximum Segment Lifetime (MSL) and that the MSL is less than 4.55
     hours we can reasonably assume that ISN's will be unique.
     */
    static func isn() -> SequenceNumber
    {
        let epochTimeIntervalInSeconds = Date().timeIntervalSince1970
        let microseconds = epochTimeIntervalInSeconds * 1000000
        let fourMicroseconds = microseconds / 4
        let wholeMicroseconds = fourMicroseconds.truncatingRemainder(dividingBy: Double(UInt32.max))
        let uint32 = UInt32(wholeMicroseconds)
        return SequenceNumber(uint32)
    }
    
    let tcpLogger: Puppy?
    let proxy: TcpProxy
    let localAddress: IPv4Address
    let localPort: UInt16

    let remoteAddress: IPv4Address
    let remotePort: UInt16

    let conduit: Conduit
    let connection: Transmission.Connection
    
    var downstreamStraw: TCPDownstreamStraw
    var upstreamStraw: TCPUpstreamStraw

    var lastUsed: Date

    var open: Bool = true

    // https://flylib.com/books/en/3.223.1.188/1/
    var state: States

    var retransmissionQueue: [InternetProtocols.TCP] = []

    var timeWaitTimer: Timer? = nil
    var retransmissionTimer: Timer? = nil

    // init() automatically send a syn-ack back for the syn (we only open a connect on receiving a syn)
    public init(proxy: TcpProxy, localAddress: IPv4Address, localPort: UInt16, remoteAddress: IPv4Address, remotePort: UInt16, conduit: Conduit, connection: Transmission.Connection, irs: SequenceNumber, tcpLogger: Puppy?, rcvWnd: UInt16) throws
    {
        print("\n* TCPProxyConnection init")
        self.proxy = proxy
        self.localAddress = localAddress
        self.localPort = localPort

        self.remoteAddress = remoteAddress
        self.remotePort = remotePort

        self.conduit = conduit
        self.connection = connection

        self.lastUsed = Date() // now

        self.state = .synReceived

        let iss = Self.isn()

        let sequenceNumber = iss.increment()
        let acknowledgementNumber = irs.increment()

        self.downstreamStraw = TCPDownstreamStraw(segmentStart: sequenceNumber, windowSize: rcvWnd)
        self.upstreamStraw = TCPUpstreamStraw(segmentStart: acknowledgementNumber)

        self.tcpLogger = tcpLogger

        try self.sendSynAck(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, conduit)

        Task
        {
            while self.open {
                self.pumpUpstream()
            }
        }

        Task
        {
            while self.open {
                self.pumpDownstream()
            }
        }

        Task
        {
            while self.open {
                self.pumpAck()
            }
        }

        tcpLogger?.debug("* TCPProxyConnection init complete\n")
    }

    // This is called for everything except the first syn received.
    public func processUpstreamPacket(_ tcp: InternetProtocols.TCP) throws
    {
        // For the most part, we can only handle packets that are inside the TCP window.
        // Otherwise, they might be old packets from a previous connection or redundant retransmissions.
        if self.upstreamStraw.inWindow(tcp)
        {
            if tcp.rst
            {
                print("* Persona.processLocalPacket: received rst")
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
                return
            }
            else if tcp.syn
            {
                print("* Persona.processLocalPacket: received syn in the update window, sending rst")
                /*
                 If the SYN is in the window it is an error, send a reset, any
                 outstanding RECEIVEs and SEND should receive "reset" responses,
                 all segment queues should be flushed, the user should also
                 receive an unsolicited general "connection reset" signal, enter
                 the CLOSED state, delete the TCB, and return.
                 */

                try self.sendRst(self.conduit, tcp, States.closed)
                self.close()
                return
            }
            else if tcp.ack
            {
                print("* Persona.processLocalPacket: received ack")
                
                switch state
                {
                    case .synReceived:
                        print("* Persona.processLocalPacket: synReceived state")
                        /*
                         SYN-RECEIVED STATE

                         If SND.UNA =< SEG.ACK =< SND.NXT then enter ESTABLISHED state
                         and continue processing.

                         If the segment acknowledgment is not acceptable, form a
                         reset segment,

                         <SEQ=SEG.ACK><CTL=RST>

                         and send it.
                         */

                        // FIXME - deal with duplicate SYNs
//                        if (self.sndUna <= SequenceNumber(tcp.acknowledgementNumber)) && (SequenceNumber(tcp.acknowledgementNumber) <= self.sndNxt)
//                        {
//                            print("✅ Persona.processLocalPacket: state set to established")
//                            self.state = .established
//                        }
//                        else
//                        {
                        print("🛑 Syn received state but the segment acknowledgment is not acceptable. Sending reset.")
                        try self.sendRst(self.conduit, tcp, self.state)

                        return
//                        }

                    case .established, .finWait1, .finWait2, .closeWait, .closing, .lastAck, .timeWait:
                        print("* Persona.processLocalPacket: .established, .finWait1, .finWait2, .closeWait, .closing, .lastAck, .timeWait state")
                        /*
                         ESTABLISHED STATE
                         */

                        try self.downstreamStraw.clear(tcp: tcp)

                        // Additional processing for specific states
                        switch state
                        {
                            case .established, .finWait1, .finWait2:
                                print("* Persona.processLocalPacket: .established, .finWait1, .finWait2 state")
                                /*
                                 Once in the ESTABLISHED state, it is possible to deliver segment
                                 text to user RECEIVE buffers.  Text from segments can be moved
                                 into buffers until either the buffer is full or the segment is
                                 empty.  If the segment empties and carries an PUSH flag, then
                                 the user is informed, when the buffer is returned, that a PUSH
                                 has been received.
                                 */

                                if tcp.payload != nil
                                {
                                    self.tcpLogger?.debug("* Persona.processLocalPacket: tcp payload received on an established connection, buffering 🏆")
                                    // If a write to the server fails, the the server connection is closed.
                                    // Start closing the client connection.

                                    print("* Persona.processLocalPacket: payload upstream write complete")
                                }

                                try self.upstreamStraw.write(tcp)

                                /*
                                 When the TCP takes responsibility for delivering the data to the
                                 user it must also acknowledge the receipt of the data.
                                 */

                                /*
                                 Once the TCP takes responsibility for the data it advances
                                 RCV.NXT over the data accepted, and adjusts RCV.WND as
                                 apporopriate to the current buffer availability.  The total of
                                 RCV.NXT and RCV.WND should not be reduced.

                                 Please note the window management suggestions in section 3.7.
                                 */

                                /*
                                 Send an acknowledgment of the form:

                                 <SEQ=SND.NXT><ACK=RCV.NXT><CTL=ACK>

                                 This acknowledgment should be piggybacked on a segment being
                                 transmitted if possible without incurring undue delay.
                                 */

                                let sndNxt = self.downstreamStraw.sequenceNumber
                                let rcvNxt = self.upstreamStraw.acknowledgementNumber

                                self.tcpLogger?.debug("processLocalPacket() called")

                                try self.sendPacket(sequenceNumber: sndNxt, acknowledgementNumber: rcvNxt, ack: true)

                                switch state
                                {
                                    case .finWait1:
                                        print("* Persona.processLocalPacket: finWait1 state")
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
                                        print("* Persona.processLocalPacket: finWait2 state")
                                        /*
                                         FIN-WAIT-2 STATE

                                         In addition to the processing for the ESTABLISHED state, if
                                         the retransmission queue is empty, the user's CLOSE can be
                                         acknowledged ("ok") but do not delete the TCB.
                                         */

                                        // Nothing for us to do here in our implementation.
                                        return

                                    default:
                                        return
                                }

                            case .closeWait:
                                print("* Persona.processLocalPacket: closeWait state")
                                /*
                                 CLOSE-WAIT STATE

                                 Do the same processing as for the ESTABLISHED state.
                                 */

                                return

                            case .closing:
                                print("* Persona.processLocalPacket: closing state")
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
                                print("* Persona.processLocalPacket: lastAck state")
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

                // The client has closed the connection.
                // The client will send no more data after this packet.
                // However, the FIN packet may have its own payload.
                if tcp.fin
                {
                    print("🛑 Persona.processLocalPacket: tcp.fin")
                    // Closing the client TCP connection takes a while.
                    // We will close the connection to the server when we have finished closing the connection to the client.
                    // In the meantime, tidy up the loose ends of closing the connection:
                    // - send our own fin to the client, if necessary
                    // - retransmit un-acked data
                    // - ack incoming fin packets
                    switch self.state
                    {
                        // FIXME - don't we need to send a fin?
                        case .synReceived, .established:
                            self.state = .closeWait

                        case .finWait1:
                            if self.retransmissionQueue.isEmpty
                            {
                                self.state = .timeWait
                                self.startTimeWaitTimer()
                                self.cancelOtherTimers()
                            }
                            else
                            {
                                self.state = .closing
                            }

                        case .finWait2:
                            self.state = .timeWait
                            self.startTimeWaitTimer()
                            self.cancelOtherTimers()

                        case .closeWait, .closing, .lastAck:
                            return

                        case .timeWait:
                            self.restartTimeWaitTimer()

                        default:
                            return
                    }
                }
            }
            else
            {
                /*
                 if the ACK bit is off drop the segment and return
                 */
                print("🛑 Persona.processLocalPacket: ACK bit is off, dropping the packet")
                
                return
            }
        }
        else
        {
            print("* Persona.processLocalPacket: NOT inWindow")
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
                print("* Persona.processLocalPacket: incoming segment is not acceptable, rst bit received, dropping packet")
                // If the rst bit is set, do not send an ack, drop the unacceptable segment and return
                return
            }
            else
            {
                print("* Persona.processLocalPacket: incoming segment is not acceptable, and no rst bit, sending ack and dropping packet")

                let sndNxt = self.downstreamStraw.sequenceNumber
                let rcvNxt = self.upstreamStraw.acknowledgementNumber

                // Send an ack
                try self.sendPacket(sequenceNumber: sndNxt, acknowledgementNumber: rcvNxt, ack: true)
                // Drop the unacceptable segment
                return
            }
        }
    }

    public func close()
    {
        self.open = false
        self.connection.close()

        AsyncAwaitThrowingEffectSynchronizer.sync
        {
            await self.proxy.removeConnection(self)
        }
    }

    func filterRetransmissions(_ ack: SequenceNumber)
    {
        self.retransmissionQueue = self.retransmissionQueue.filter
        {
            (tcp: InternetProtocols.TCP) -> Bool in

            let expectedAck = SequenceNumber(tcp.sequenceNumber).add(Int(TcpProxy.sequenceLength(tcp)))
            return ack < expectedAck // Keep packets which have not been acked
        }
    }

    func pumpUpstream()
    {
        do
        {
            let segment = try self.upstreamStraw.read()

            guard self.connection.write(data: segment.data) else
            {
                self.tcpLogger?.error("Upstream write failed, closing connection")
                self.close()
                return
            }

            try self.upstreamStraw.clear(segment: segment)
        }
        catch
        {
            self.close()
            return
        }
    }

    func pumpDownstream()
    {
        let windowSize = self.downstreamStraw.windowSize

        // If a read from the server connection fails, the the server connection is closed.
        guard let data = self.connection.read(maxSize: Int(windowSize)) else
        {
            // Fully close the server connection and let users know the connection is closed if they try to write data.
            self.close()

            // Start to close the client connection.
            // FIXME - find the right acknowledgeNumber for this.
//                try self.startClose(sequenceNumber: self.sndNxt, acknowledgementNumber: SequenceNumber(tcp.sequenceNumber))

            return
        }

        self.processDownstreamPacket(data)
    }

    func pumpAck()
    {
        let ackSequenceNumber = self.upstreamStraw.acknowledgementNumber
        let sequenceNumber = self.downstreamStraw.sequenceNumber

        tcpLogger?.debug("* acking cleared bytes \(sequenceNumber) \(ackSequenceNumber)")

        do
        {
            try self.sendPacket(sequenceNumber: sequenceNumber, acknowledgementNumber: ackSequenceNumber, ack: true)
        }
        catch
        {
            tcpLogger?.debug("! Error: failed to send ack \(sequenceNumber) \(ackSequenceNumber), closing stream")

            self.close()
            return
        }
    }

    func processDownstreamPacket(_ data: Data)
    {
        do
        {
            let windowSize = self.downstreamStraw.windowSize

            let tcp = try InternetProtocols.TCP(sourcePort: self.remotePort, destinationPort: self.localPort, windowSize: windowSize, payload: data)
            guard let ipv4 = try InternetProtocols.IPv4(sourceAddress: self.remoteAddress, destinationAddress: self.localAddress, payload: tcp.data, protocolNumber: .TCP) else
            {
                self.tcpLogger?.error("Error making downstream IPv4 packet")
                return
            }

            let message = Message.IPDataV4(ipv4.data)
            self.conduit.flowerConnection.writeMessage(message: message)

            self.lastUsed = Date() // now
        }
        catch
        {
            self.tcpLogger?.error("Error sending downstream packet \(error)")
            return
        }
    }

    func sendSynAck(sequenceNumber: SequenceNumber, acknowledgementNumber: SequenceNumber, _ conduit: Conduit) throws
    {
        tcpLogger?.debug("* sending SynAck")
        try self.sendPacket(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, syn: true, ack: true)
    }

    func sendAck(_ tcp: InternetProtocols.TCP, _ state: States) throws
    {
        tcpLogger?.debug("* sending Ack")
        let sndNxt = self.downstreamStraw.sequenceNumber
        let rcvNxt = self.upstreamStraw.acknowledgementNumber

        try self.sendPacket(sequenceNumber: sndNxt, acknowledgementNumber: rcvNxt, syn: true, ack: true)
    }

    func sendRst(_ conduit: Conduit, _ tcp: InternetProtocols.TCP, _ state: States) throws
    {
        tcpLogger?.debug("* sending Rst")
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
                    self.tcpLogger?.debug("sendRst() called")
                    try self.sendPacket(sequenceNumber: SequenceNumber(tcp.acknowledgementNumber), rst: true)
                }
                else
                {
                    let acknowledgementNumber = SequenceNumber(tcp.sequenceNumber).add(TcpProxy.sequenceLength(tcp))
                    self.tcpLogger?.debug("sendRst() called")
                    try self.sendPacket(acknowledgementNumber: acknowledgementNumber, ack: true, rst: true)
                }

            case .synReceived:
                /*
                 If the segment acknowledgment is not acceptable, form a
                 reset segment,

                 <SEQ=SEG.ACK><CTL=RST>

                 and send it.
                 */
                self.tcpLogger?.debug("sendRst() called")
                try self.sendPacket(sequenceNumber: SequenceNumber(tcp.acknowledgementNumber), rst: true)

            default:
                return // FIXME
        }
    }

    func startClose(sequenceNumber: SequenceNumber, acknowledgementNumber: SequenceNumber) throws
    {
        self.state = .finWait1
        self.tcpLogger?.debug("startClose() called")
        try self.sendFin(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber)
    }

    func sendFin(sequenceNumber: SequenceNumber, acknowledgementNumber: SequenceNumber) throws
    {
        self.tcpLogger?.debug("sendFin() called")
        try self.sendPacket(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, ack: true, fin: true)
    }

    func sendPacket(sequenceNumber: SequenceNumber = SequenceNumber(0), acknowledgementNumber: SequenceNumber = SequenceNumber(0), syn: Bool = false, ack: Bool = false, fin: Bool = false, rst: Bool = false) throws
    {
        do
        {
            let windowSize = self.upstreamStraw.windowSize

            if self.remotePort == 2234 // Print traffic to the TCP Echo Server to the TCP log for debugging
            {
                self.tcpLogger?.debug("*** Creating an IPv4 packet ***")
                self.tcpLogger?.debug("* source address: \(self.remoteAddress.string):\(self.remotePort)")
                self.tcpLogger?.debug("* destination address: \(self.localAddress.string):\(self.localPort)")
                self.tcpLogger?.debug("* sequenceNumber:")
                self.tcpLogger?.debug("* \(sequenceNumber.uint32)")
                self.tcpLogger?.debug("* \(sequenceNumber.data.hex)")
                self.tcpLogger?.debug("* acknowledgementNumber:")
                self.tcpLogger?.debug("* \(acknowledgementNumber.uint32)")
                self.tcpLogger?.debug("* \(acknowledgementNumber.data.hex)")
                self.tcpLogger?.debug("* syn: \(syn)")
                self.tcpLogger?.debug("* ack: \(ack)")
                self.tcpLogger?.debug("* fin: \(fin)")
                self.tcpLogger?.debug("* rst: \(rst)")
                self.tcpLogger?.debug("* window size \(windowSize)")
            }
            
            guard let ipv4 = try IPv4(sourceAddress: self.remoteAddress, destinationAddress: self.localAddress, sourcePort: self.remotePort, destinationPort: self.localPort, sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, syn: syn, ack: ack, fin: fin, rst: rst, windowSize: windowSize, payload: nil) else
            {
                self.tcpLogger?.debug("* sendPacket() failed to initialize IPv4 packet.")
                throw TcpProxyError.badIpv4Packet
            }
            
            self.tcpLogger?.debug("* IPv4 Packet created 💖")
            
            let message = Message.IPDataV4(ipv4.data)
            
            self.tcpLogger?.debug("* IPDataV4 Message created: \(message)")
            self.tcpLogger?.debug("************************************************************\n")
            self.conduit.flowerConnection.writeMessage(message: message)
        }
        catch
        {
            self.tcpLogger?.debug("* sendPacket() failed to initialize IPv4 packet. Received an error: \(error)")
            throw error
        }
    }

    func startTimeWaitTimer()
    {
        self.timeWaitTimer = Timer(timeInterval: TcpProxy.maximumSegmentLifetime * 2, repeats: false)
        {
            timer in

            self.close()
        }
    }

    func restartTimeWaitTimer()
    {
        if let timeWaitTimer = self.timeWaitTimer
        {
            timeWaitTimer.invalidate()
        }

        self.startTimeWaitTimer()
    }

    func cancelOtherTimers()
    {
        // FIXME
        return
    }
}
