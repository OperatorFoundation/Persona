//
//  TcpProxyConnection.swift
//  
//
//  Created by Dr. Brandon Wiley on 3/11/22.
//
import Foundation
import Logging

import Chord
import InternetProtocols
import Net
import Puppy
import SwiftHexTools
import TransmissionAsync

public class TcpProxyConnection
{
    // These static properties and functions handle caching connections to the tcpproxy subsystem.
    // We need one connection to the tcpproxy subsystem for each source address/port pair.
    static var connections: [TcpIdentity: TcpProxyConnection] = [:]

    static public func getConnection(identity: TcpIdentity, downstream: AsyncConnection, ipv4: IPv4, tcp: TCP, payload: Data?, logger: Logger, tcpLogger: Puppy, writeLogger: Puppy) async throws -> TcpProxyConnection
    {
        if let connection = Self.connections[identity]
        {
//            logger.debug("TcpProxyConnection.getConnection: existing - \(ipv4.sourceAddress.ipv4AddressString ?? "not an IPv4 address"):\(tcp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "not an IPv4 address"):\(tcp.destinationPort)")
//            if tcp.destinationPort == 7 || tcp.destinationPort == 853
//            {
//                tcpLogger.debug("TcpProxyConnection.processDownstreamPacket: existing - \(ipv4.sourceAddress.ipv4AddressString ?? "not an IPv4 address"):\(tcp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "not an IPv4 address"):\(tcp.destinationPort)")
//            }

            return connection
        }
        else
        {
//            logger.debug("TcpProxyConnection.getConnection: new attempt, need SYN - \(ipv4.sourceAddress.ipv4AddressString ?? "not an IPv4 address"):\(tcp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "not an IPv4 address"):\(tcp.destinationPort)")
//            if tcp.destinationPort == 7 || tcp.destinationPort == 853
//            {
//                tcpLogger.debug("TcpProxyConnection.processDownstreamPacket: new attempt, need SYN - \(ipv4.sourceAddress.ipv4AddressString ?? "not an IPv4 address"):\(tcp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "not an IPv4 address"):\(tcp.destinationPort)")
//            }

            guard tcp.syn, !tcp.ack, !tcp.rst, !tcp.fin else
            {
//                logger.debug("rejected packet - SYN:\(tcp.syn) ACK:\(tcp.ack) RST:\(tcp.rst) FIN:\(tcp.fin)")
//                if tcp.destinationPort == 7 || tcp.destinationPort == 853
//                {
//                    tcpLogger.debug("rejected packet - SYN:\(tcp.syn) ACK:\(tcp.ack) RST:\(tcp.rst) FIN:\(tcp.fin)")
//                }
//
//                logger.debug("new TcpProxyConnection cancelled due to lack of SYN")
//                if tcp.destinationPort == 7 || tcp.destinationPort == 853
//                {
//                    tcpLogger.debug("new TcpProxyConnection cancelled due to lack of SYN")
//                }

                throw TcpProxyConnectionError.badFirstPacket
            }

//            logger.debug("TcpProxyConnection.getConnection: new with SYN - \(ipv4.sourceAddress.ipv4AddressString ?? "not an IPv4 address"):\(tcp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "not an IPv4 address"):\(tcp.destinationPort)")
//            if tcp.destinationPort == 7 || tcp.destinationPort == 853
//            {
//                tcpLogger.debug("TcpProxyConnection.processDownstreamPacket: new with SYN - \(ipv4.sourceAddress.ipv4AddressString ?? "not an IPv4 address"):\(tcp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "not an IPv4 address"):\(tcp.destinationPort)")
//            }

            let connection = try await TcpProxyConnection(identity: identity, downstream: downstream, ipv4: ipv4, tcp: tcp, payload: payload, logger: logger, tcpLogger: tcpLogger, writeLogger: writeLogger)
            Self.connections[identity] = connection
            return connection
        }
    }

    static public func removeConnection(identity: TcpIdentity)
    {
//        if let connection = self.connections[identity]
//        {
//            connection.logger.debug("TcpProxyConnection.removeConnection: \(identity.localAddress.data.ipv4AddressString ?? "?.?.?.?"):\(identity.localPort) -> \(identity.remoteAddress.data.ipv4AddressString ?? "?.?.?.?"):\(identity.remotePort)")
//            if identity.remotePort == 7 || identity.remotePort == 853
//            {
//                connection.tcpLogger.debug("TcpProxyConnection.removeConnection: \(identity.localAddress.data.ipv4AddressString ?? "?.?.?.?"):\(identity.localPort) -> \(identity.remoteAddress.data.ipv4AddressString ?? "?.?.?.?"):\(identity.remotePort)")
//            }
//        }

        self.connections.removeValue(forKey: identity)
    }
    // End of static section

    public let identity: TcpIdentity

    let downstream: AsyncConnection
    let upstream: AsyncConnection
    let logger: Logger
    let tcpLogger: Puppy
    let writeLogger: Puppy

    // https://flylib.com/books/en/3.223.1.188/1/
    var state: TcpStateHandler

    // init() automatically send a syn-ack back for the syn (we only open a connect on receiving a syn)
    public init(identity: TcpIdentity, downstream: AsyncConnection, ipv4: IPv4, tcp: TCP, payload: Data?, logger: Logger, tcpLogger: Puppy, writeLogger: Puppy) async throws
    {
//        logger.debug("TcpProxyConnection.init: \(identity.localAddress.data.ipv4AddressString ?? "?.?.?.?"):\(identity.localPort) -> \(identity.remoteAddress.data.ipv4AddressString ?? "?.?.?.?"):\(identity.remotePort)")
//        if identity.remotePort == 7 || identity.remotePort == 853
//        {
//            tcpLogger.debug("TcpProxyConnection.init: \(identity.localAddress.data.ipv4AddressString ?? "?.?.?.?."):\(identity.localPort) -> \(identity.remoteAddress.data.ipv4AddressString ?? "?.?.?.?."):\(identity.remotePort)")
//        }

        self.identity = identity
        self.downstream = downstream
        self.logger = logger
        self.tcpLogger = tcpLogger
        self.writeLogger = writeLogger

        let hostBytes = ipv4.destinationAddress
        guard let portBytes = tcp.destinationPort.maybeNetworkData else
        {
            throw TcpProxyError.dataConversionFailed
        }

        // tcpproxy subsystem expects 4-byte address and 2-byte port
        let bytes = hostBytes + portBytes

//        self.logger.trace("TcpProxyConnection.init - connecting to tcpproxy subsystem")

        self.upstream = try await AsyncTcpSocketConnection("127.0.0.1", 1232, self.logger)

//        self.logger.trace("TcpProxyConnection.init - connected to tcpproxy subsystem")

//        self.logger.debug("TcpProxyConnection.init - Writing \(bytes.count) bytes to the TCP Proxy Server: \(bytes.hex)")
//        if tcp.destinationPort == 7 || tcp.destinationPort == 853
//        {
//            self.tcpLogger.debug("TcpProxyConnection.init - Writing \(bytes.count) bytes to the TCP Proxy Server: \(bytes.hex)")
//        }

        // Here is where we actually write the TCP destination to the tcpproxy subsystem.
        try await upstream.write(bytes)

//        self.logger.debug("TcpProxyConnection.init - Write to tcpproxy successful")
//        if tcp.destinationPort == 7 || tcp.destinationPort == 853
//        {
//            self.tcpLogger.debug("TcpProxyConnection.init - Write to tcpproxy successful")
//        }

//        self.logger.debug("TcpProxyConnection.init - Reading 1 status byte from tcpproxy")
//        if tcp.destinationPort == 7 || tcp.destinationPort == 853
//        {
//            self.tcpLogger.debug("TcpProxyConnection.init - Reading 1 status byte from tcpproxy")
//        }

        let connectionStatusData = try await upstream.readSize(1)
        let connectionStatusByte = connectionStatusData[0]
        guard let connectionStatus = ConnectionStatus(rawValue: connectionStatusByte) else
        {
            throw TcpProxyError.unknownConnectionStatus(connectionStatusByte)
        }

//        self.logger.debug("TcpProxyConnection.init - Read 1 status byte from tcpproxy successfully")
//        if tcp.destinationPort == 7 || tcp.destinationPort == 853
//        {
//            self.tcpLogger.debug("TcpProxyConnection.init - Read 1 status byte from tcpproxy successfully")
//        }

        guard connectionStatus == .success else
        {
//            self.logger.debug("TcpProxyConnection.init - tcpproxy status was failure")
//            if tcp.destinationPort == 7 || tcp.destinationPort == 853
//            {
//                self.tcpLogger.debug("TcpProxyConnection.init - tcpstatus was failure")
//            }

            throw TcpProxyError.upstreamConnectionFailed
        }

//        self.logger.debug("TcpProxyConnection.init - tcpproxy status was success")
//        if tcp.destinationPort == 7 || tcp.destinationPort == 853
//        {
//            self.tcpLogger.debug("TcpProxyConnection.init - tcpstatus was success")
//        }

        self.state = TcpListen(identity: identity, logger: logger, tcpLogger: tcpLogger, writeLogger: writeLogger)

//        logger.debug("TcpProxyConnection.init::\(self.state) \(description(ipv4, tcp))")
//        if identity.remotePort == 7 || identity.remotePort == 853
//        {
//            tcpLogger.debug("TcpProxyConnection.init: \(description(ipv4, tcp))")
//        }

//        self.logger.debug("TcpProxyConnection.init[\(self.state)] - \(description(ipv4, tcp))")

        let transition = try await self.state.processDownstreamPacket(ipv4: ipv4, tcp: tcp, payload: nil)

        self.logger.debug("! \(self.state) => \(transition.newState), \(transition.packetsToSend.count) packets to send")

        for packet in transition.packetsToSend
        {
            let outPacket = Packet(ipv4Bytes: packet.data, timestamp: Date())
            if let outTcp = outPacket.tcp
            {
                self.logger.debug("<- \(description(packet, outTcp))")
            }

            try await self.sendPacket(packet)
        }

//        let oldState = self.state
        self.state = transition.newState

//        logger.debug("TcpProxyConnection.init: \(oldState) => \(self.state), \(transition.packetsToSend.count) packets sent downstream")
//        if identity.remotePort == 7 || identity.remotePort == 853
//        {
//            tcpLogger.debug("TcpProxyConnection.init: \(oldState) => \(self.state), \(transition.packetsToSend.count) packets sent downstream")
//        }

        guard self.state.open else
        {
            self.logger.debug("TcpProxyConnection.init - connection was closed immediately!")
            if tcp.destinationPort == 7 || tcp.destinationPort == 853
            {
                self.tcpLogger.debug("TcpProxyConnection.init - connection was closed immediately!")
            }

            throw TcpProxyConnectionError.tcpClosed
        }

//        Asynchronizer.async
//        {
//            while self.state.open
//            {
//                dp
//                {
//                    try await self.pumpUpstreamToUpstreamStraw()
//                }
//                catch
//                {
//                    self.logger.error("Error in pumpUpstreamToUpstreamStraw")
//                }
//            }
//        }

//
//        Task
//        {
//            while self.state.open
//            {
//                try await self.pumpDownstream()
//            }
//        }

        // FIXME: Don't call this in a loop
//        Task
//        {
//            while self.open {
//                self.pumpAck()
//            }
//        }
    }

    public func processDownstreamPacket(ipv4: IPv4, tcp: TCP, payload: Data?) async throws
    {
//        self.logger.debug("TcpProxyConnection.processDownstreamPacket[\(self.state)] - \(description(ipv4, tcp))")
        let transition = try await self.state.processDownstreamPacket(ipv4: ipv4, tcp: tcp, payload: nil)
//        self.logger.debug("TcpProxyConnection.processDownstreamPacket - returned from current TCP state processDownstreamPacket()")

        self.logger.debug("@ \(self.state) => \(transition.newState), \(transition.packetsToSend.count) packets to send")
        
        for packet in transition.packetsToSend
        {
            let outPacket = Packet(ipv4Bytes: packet.data, timestamp: Date())
            if let outTcp = outPacket.tcp
            {
                self.logger.debug("<- \(description(packet, outTcp))")
            }

            try await self.sendPacket(packet)
        }
        
//        self.logger.debug("TcpProxyConnection - processDownstreamPacket: sent \(transition.packetsToSend.count) packets.")
//        let oldState = self.state
        self.state = transition.newState
//        self.logger.debug("TcpProxyConnection - processDownstreamPacket: transitioned to a new state - \(self.state)")

//        logger.debug("TcpProxyConnection.processDownstreamPacket: \(oldState) => \(self.state), \(transition.packetsToSend.count) packets sent downstream")
//        if identity.remotePort == 7 || identity.remotePort == 853
//        {
//            tcpLogger.debug("TcpProxyConnection.init: \(oldState) => \(self.state), \(transition.packetsToSend.count) packets sent downstream")
//        }

        guard self.state.open else
        {
            self.logger.debug("TcpProxyConnection.processDownstreamPacket - connection was closed")
            if tcp.destinationPort == 7 || tcp.destinationPort == 853
            {
                self.tcpLogger.debug("TcpProxyConnection.processDownstreamPacket - connection was closed")
            }

            try! await self.upstream.close()
            Self.removeConnection(identity: self.identity)

            throw TcpProxyConnectionError.tcpClosed
        }
        
//        self.logger.debug("TcpProxyConnection - processDownstreamPacket: finished")

        if let upstreamStraw = self.state.upstreamStraw
        {
            let count = await upstreamStraw.count()
            if count > 0
            {
                let segment = try await upstreamStraw.read()
                try await self.upstream.write(segment.data)
                try await upstreamStraw.clear(segment: segment)
            }
        }
    }

    func pumpUpstreamStrawToUpstream() async throws
    {
        do
        {
            guard let upstreamStraw = self.state.upstreamStraw else
            {
                return
            }

            let segment = try await upstreamStraw.read()

            do
            {
                self.logger.info("\(segment.data.count) bytes : Persona --> tcpproxy")
                try await self.upstream.writeWithLengthPrefix(segment.data, 32)
            }
            catch
            {
                self.logger.error("Upstream write failed, closing connection")
                self.tcpLogger.error("Upstream write failed, closing connection")
                let _ = self.state.panicOnUpstreamClose() // FIXME
                return
            }

            self.logger.debug("\n* Sent received data (\(segment.data.count) bytes) upstream.")
            self.logger.debug("* Data sent upstream: \n\(segment.data.hex)\n")

            try await upstreamStraw.clear(segment: segment)
        }
        catch
        {
            let _ = self.state.panicOnUpstreamClose() // FIXME
            return
        }
    }

    func pumpUpstreamToUpstreamStraw() async throws
    {
        guard let downstreamStraw = self.state.downstreamStraw else
        {
            return
        }

        do
        {
            let segment = try await self.upstream.readWithLengthPrefix(prefixSizeInBits: 32)
            self.logger.info("\(segment.data.count) bytes : Persona <-- tcpproxy")

            self.logger.debug("\n* Sent received data (\(segment.data.count) bytes) upstream.")
            self.logger.debug("* Data sent upstream: \n\(segment.data.hex)\n")

            try await downstreamStraw.write(segment)
        }
        catch
        {
            self.logger.error("Upstream write failed, closing connection")
            self.tcpLogger.error("Upstream write failed, closing connection")
            let _ = self.state.panicOnUpstreamClose() // FIXME
            return
        }
    }


//    func pumpDownstream() async throws
//    {
//        let windowSize = self.downstreamStraw.windowSize
//
//        // If a read from the server connection fails, the the server connection is closed.
//        do
//        {
//            let data = try await self.upstream.readWithLengthPrefix(prefixSizeInBits: 32)
//            try await self.processDownstreamPacket(data)
//        }
//        catch
//        {
//            // Fully close the server connection and let users know the connection is closed if they try to write data.
//            try await self.closeUpstream()
//
//            // Start to close the client connection.
//            // FIXME - find the right acknowledgeNumber for this.
////                try self.startClose(sequenceNumber: self.sndNxt, acknowledgementNumber: SequenceNumber(tcp.sequenceNumber))
//
//            return
//        }
//    }
//
//    func pumpAck() async throws
//    {
//        let ackSequenceNumber = self.upstreamStraw.acknowledgementNumber
//        let sequenceNumber = self.downstreamStraw.sequenceNumber
//
//        do
//        {
//            try await self.sendPacket(sequenceNumber: sequenceNumber, acknowledgementNumber: ackSequenceNumber, ack: true)
//        }
//        catch
//        {
//            tcpLogger?.debug("! Error: failed to send ack \(sequenceNumber) \(ackSequenceNumber), closing stream")
//
//            try await self.closeUpstream()
//            return
//        }
//    }
//
//    func processDownstreamPacket(_ data: Data) async throws
//    {
//        do
//        {
//            try await self.sendPacket(sequenceNumber: self.downstreamStraw.sequenceNumber, acknowledgementNumber: self.upstreamStraw.acknowledgementNumber, ack: true, payload: data)
//            try self.downstreamStraw.clear(bytesSent: data.count)
//        }
//        catch
//        {
//            self.tcpLogger?.error("Error sending downstream packet \(error)")
//            return
//        }
//        
//        self.lastUsed = Date() // now
//    }

//    func sendAck(_ tcp: InternetProtocols.TCP, _ state: States) async throws
//    {
//        let sndNxt = self.downstreamStraw.sequenceNumber
//        let rcvNxt = self.upstreamStraw.acknowledgementNumber
//
//        try await self.sendPacket(sequenceNumber: sndNxt, acknowledgementNumber: rcvNxt, syn: true, ack: true)
//    }

//    func sendRst(_ tcp: InternetProtocols.TCP, _ state: States) async throws
//    {
//        tcpLogger?.debug("* sending Rst")
//        switch state
//        {
//            case .closed:
//                /*
//                 If the state is CLOSED (i.e., TCB does not exist) then
//
//                 all data in the incoming segment is discarded.  An incoming
//                 segment containing a RST is discarded.  An incoming segment not
//                 containing a RST causes a RST to be sent in response.  The
//                 acknowledgment and sequence field values are selected to make the
//                 reset sequence acceptable to the TCP that sent the offending
//                 segment.
//
//                 If the ACK bit is off, sequence number zero is used,
//
//                 <SEQ=0><ACK=SEG.SEQ+SEG.LEN><CTL=RST,ACK>
//
//                 If the ACK bit is on,
//
//                 <SEQ=SEG.ACK><CTL=RST>
//
//                 Return.
//                 */
//
//                if tcp.rst
//                {
//                    return
//                }
//                else if tcp.ack
//                {
//                    self.tcpLogger?.debug("sendRst() called")
//                    try await self.sendPacket(sequenceNumber: SequenceNumber(tcp.acknowledgementNumber), rst: true)
//                }
//                else
//                {
//                    let acknowledgementNumber = SequenceNumber(tcp.sequenceNumber).add(TcpProxy.sequenceLength(tcp))
//                    self.tcpLogger?.debug("sendRst() called")
//                    try await self.sendPacket(acknowledgementNumber: acknowledgementNumber, ack: true, rst: true)
//                }
//
//            case .synReceived:
//                /*
//                 If the segment acknowledgment is not acceptable, form a
//                 reset segment,
//
//                 <SEQ=SEG.ACK><CTL=RST>
//
//                 and send it.
//                 */
//                self.tcpLogger?.debug("sendRst() called")
//                try await self.sendPacket(sequenceNumber: SequenceNumber(tcp.acknowledgementNumber), rst: true)
//
//            default:
//                return // FIXME
//        }
//    }

//    func closeDownstream() async throws
//    {
//        self.logger.info("closing downstream")
//
//        self.state = .finWait1
//        self.tcpLogger?.debug("startClose() called")
//        try await self.sendFinAck(sequenceNumber: self.downstreamStraw.sequenceNumber, acknowledgementNumber: self.upstreamStraw.acknowledgementNumber)
//    }
//
//    func sendFinAck(sequenceNumber: SequenceNumber, acknowledgementNumber: SequenceNumber) async throws
//    {
//        self.tcpLogger?.debug("sendFin() called")
//        try await self.sendPacket(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, ack: true, fin: true)
//    }
//
//    func handleNewConnection(tcp: InternetProtocols.TCP, sourceAddress: IPv4Address, sourcePort: UInt16, destinationAddress: IPv4Address, destinationPort: UInt16) async throws
//    {
//        // When we receive a packet bound for a new destination,
//        // if we can connect to that destination,
//        //      we respond as if we are in the LISTEN state
//        // otherwise,
//        //      we respond as if we are in the CLOSED state
//
//        if tcp.rst
//        {
//            /*
//             If the state is LISTEN then
//
//             first check for an RST
//
//             An incoming RST should be ignored.  Return.
//             */
//
//            return
//        }
//        else if tcp.ack
//        {
//            /*
//             second check for an ACK
//
//             Any acknowledgment is bad if it arrives on a connection still in
//             the LISTEN state.  An acceptable reset segment should be formed
//             for any arriving ACK-bearing segment.  The RST should be
//             formatted as follows:
//
//             <SEQ=SEG.ACK><CTL=RST>
//
//             Return.
//             */
//
//            try await self.sendRst(sourceAddress: sourceAddress, sourcePort: sourcePort, destinationAddress: destinationAddress, destinationPort: destinationPort, tcp, .listen)
//            return
//        }
//        else if tcp.syn // A new connection requires a SYN packet
//        {
//            if tcp.destinationPort == 2234
//            {
//                tcpLogger.debug("\n************************************************************")
//                tcpLogger.debug("* ⮕ SYN SEQ:\(SequenceNumber(tcp.sequenceNumber)) ❣️")
//                tcpLogger.debug("\n************************************************************")
//            }
//
//            // connect() automatically send a syn-ack back for the syn internally
//            do
//            {
//            }
//            catch
//            {
//                // Connection failed.
//                self.logger.error("* Persona failed to connect to the destination address \(destinationAddress.string): \(destinationPort)")
//                try await self.sendRst(sourceAddress: sourceAddress, sourcePort: sourcePort, destinationAddress: destinationAddress, destinationPort: destinationPort, tcp, .closed)
//                return
//            }
//        }
//        else
//        {
//            /*
//             Any other control or text-bearing segment (not containing SYN)
//             must have an ACK and thus would be discarded by the ACK
//             processing.  An incoming RST segment could not be valid, since
//             it could not have been sent in response to anything sent by this
//             incarnation of the connection.  So you are unlikely to get here,
//             but if you do, drop the segment, and return.
//             */
//        }
//    }

    func sendPacket(_ ipv4: IPv4) async throws
    {
//        self.logger.info("TcpProxyConnection.sendPacket - \(ipv4.data.count) bytes")

        let packet = Packet(ipv4Bytes: ipv4.data, timestamp: Date())
        if let ipv4 = packet.ipv4, let _ = packet.tcp
        {
//            if tcp.syn
//            {
//                if tcp.ack
//                {
//                    self.logger.info("TcpProxyConnection.sendPacket - SYN-ACK")
//                }
//                else
//                {
//                    self.logger.info("TcpProxyConnection.sendPacket - SYN")
//                }
//            }
//            else if tcp.ack
//            {
//                if let payload = tcp.payload
//                {
//                    self.logger.info("TcpProxyConnection.sendPacket - ACK with \(payload.count) byte payload")
//                }
//                else
//                {
//                    self.logger.info("TcpProxyConnection.sendPacket - ACK with no payload")
//                }
//            }
//            else if tcp.fin
//            {
//                self.logger.info("TcpProxyConnection.sendPacket - FIN")
//            }
//            else if tcp.rst
//            {
//                self.logger.info("TcpProxyConnection.sendPacket - RST")
//            }
//            else if let payload = tcp.payload
//            {
//                self.logger.info("TcpProxyConnection.sendPacket - no flags, \(payload.count) byte payload")
//            }
//            else
//            {
//                self.logger.info("TcpProxyConnection.sendPacket - no flags, no payload")
//            }

            self.writeLogger.info("TcpProxyConnection.sendPacket - write \(ipv4.data.count) bytes to client")

            try await self.downstream.writeWithLengthPrefix(ipv4.data, 32)

            self.writeLogger.info("TcpProxyConnection.sendPacket - succesfully wrote \(ipv4.data.count) bytes to client")
        }
    }
}

public enum ConnectionStatus: UInt8
{
    case success = 0xF1
    case failure = 0xF0
}

public enum TcpProxyConnectionError: Error
{
    case badFirstPacket
    case tcpClosed
}
