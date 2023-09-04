//
//  TcpEstablished.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/5/23.
//

import Foundation

import InternetProtocols

public class TcpEstablished: TcpStateHandler
{
    override public func processDownstreamPacket(ipv4: IPv4, tcp: TCP, payload: Data?) async throws -> TcpStateTransition
    {
        let clientWindow = self.straw.clientWindow(size: tcp.windowSize)
        let packetLowerBound = SequenceNumber(tcp.sequenceNumber)

        var packetUpperBound: SequenceNumber = packetLowerBound
        if let payload
        {
            packetUpperBound = packetUpperBound.add(payload.count)
        }

        if tcp.syn
        {
            packetUpperBound = packetUpperBound.increment()
        }

        if tcp.fin
        {
            packetUpperBound = packetUpperBound.increment()
        }

        // We can only receive data inside the TCP window.
        guard self.straw.inWindow(tcp) else
        {
            self.logger.error("❌ \(clientWindow.lowerBound) <= \(packetLowerBound)..<\(packetUpperBound) <= \(clientWindow.upperBound)")

            let (sequenceNumber, acknowledgementNumber, windowSize) = self.getState()

            // Send an ACK to let the client know that they are outside of the TCP window.
            self.logger.info("Out of window ACK - SEQ#\(sequenceNumber), ACK#\(acknowledgementNumber)")
            let ack = try self.makePacket(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize, ack: true)
            return TcpStateTransition(newState: self, packetsToSend: [ack])
        }

        self.logger.error("✅ \(clientWindow.lowerBound) <= \(packetLowerBound)..<\(packetUpperBound) <= \(clientWindow.upperBound)")

//        self.logger.debug("TcpEstablished.processDownstreamPacket")
        /*
         Once in the ESTABLISHED state, it is possible to deliver segment
         text to user RECEIVE buffers.  Text from segments can be moved
         into buffers until either the buffer is full or the segment is
         empty.  If the segment empties and carries an PUSH flag, then
         the user is informed, when the buffer is returned, that a PUSH
         has been received.
         */

        if tcp.ack
        {
            let acknowledgementNumber = SequenceNumber(tcp.acknowledgementNumber)
            try self.straw.acknowledge(acknowledgementNumber)
        }

        if tcp.payload != nil
        {
//            self.tcpLogger.debug("* Persona.processLocalPacket: tcp payload received on an established connection, buffering 🏆")
//            self.tcpLogger.debug("* SEQ:\(SequenceNumber(tcp.sequenceNumber)) ACK:\(SequenceNumber(tcp.acknowledgementNumber))")
//
//            let payloadString = String(decoding: payload, as: UTF8.self)
//            if payloadString.isEmpty
//            {
//                self.tcpLogger.debug("* Payload (\(payload.count) bytes): [\(payload.hex)]")
//            }
//            else
//            {
//                self.tcpLogger.debug("* Payload (\(payload.count) bytes): \"\(payloadString)\" [\(payload.hex)]")
//            }

            // Write the payload to the tcpproxy subsystem
            try await self.pumpClientToServer(tcp)
            let packets = try await self.pumpServerToClient(tcp)

//            self.logger.debug("* Persona.processLocalPacket: payload upstream write complete\n")

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

            if packets.isEmpty
            {
                let ack = try await makeAck()
                self.logger.info("No server-to-client payloads ACK")
                return TcpStateTransition(newState: self, packetsToSend: [ack])
            }
            else
            {
                self.logger.info("server-to-client payloads ACK")
                return TcpStateTransition(newState: self, packetsToSend: packets)
            }
        }

        if tcp.rst
        {
            /**
             If the TCP is in one of the synchronized states (ESTABLISHED,
             FIN-WAIT-1, FIN-WAIT-2, CLOSE-WAIT, CLOSING, LAST-ACK, TIME-WAIT), it
             aborts the connection and informs its user.  We discuss this latter
             case under "half-open" connections below.
             */
            
            // FIXME: - reset connection
        }

        if tcp.fin
        {
            /// If an unsolicited FIN arrives from the network, the receiving TCP
            /// can ACK it and tell the user that the connection is closing.
            
            // Send ACK and move to CLOSE-WAIT state
            let ack = try await makeAck()
            self.logger.info("FIN ACK")
            return TcpStateTransition(newState: TcpCloseWait(self), packetsToSend: [ack])
        }

        // Stay in ESTABLISHED until we get a FIN or RST or the upstream connection closes.
        return TcpStateTransition(newState: self)
    }

    override public func processUpstreamData(data: Data) throws -> TcpStateTransition
    {
        // FIXME - pump downstream
        return TcpStateTransition(newState: self)
    }

    override public func processUpstreamClose() throws -> TcpStateTransition
    {
        // FIXME - being closing connection

        return TcpStateTransition(newState: self)
    }

    func pumpClientToServer(_ tcp: TCP) async throws
    {
        guard let payload = tcp.payload else
        {
            return
        }

        // Fully write all incoming payloads from the client to the server so that we don't have to buffer them.
        try await self.upstream.writeWithLengthPrefix(payload, 32)

        self.straw.increaseAcknowledgementNumber(payload.count)

        self.logger.info("TcpEstablished.pumpClientToServer: Persona --> tcpproxy - \(payload.count) bytes (new ACK#\(self.straw.acknowledgementNumber))")
    }

    func pumpServerToClient(_ tcp: TCP) async throws -> [IPv4]
    {
        // Buffer data from the server until the client ACKs it.
        let data = try await self.upstream.read()

        if data.count > 0
        {
            try self.straw.write(data)
            self.logger.info("TcpEstablished.pumpServerToClient: Persona <-- tcpproxy - \(data.count) bytes")
        }

        guard !self.straw.isEmpty else
        {
            return []
        }

        // We're going to split the whole buffer into individual packets.
        var packets: [IPv4] = []

        // The maximum we can send is limited by both the client window size and how much data is in the buffer.
        let sizeToSend = min(Int(tcp.windowSize), self.straw.count)

        var totalPayloadSize = 0
        var nextSequenceNumber = self.straw.sequenceNumber

        // We're going to hit this limit exactly.
        while totalPayloadSize < sizeToSend
        {
            // Each packet is limited is by the amount left to send and the MTU (which we guess).
            let nextPacketSize = min(sizeToSend - totalPayloadSize, 1400)

            let window = SequenceNumberRange(lowerBound: nextSequenceNumber, size: UInt32(nextPacketSize))
            let packet = try await self.makeAck(window: window)
            packets.append(packet)

            totalPayloadSize = totalPayloadSize + nextPacketSize
            nextSequenceNumber = nextSequenceNumber.add(nextPacketSize)
        }

        return packets
    }
}

public enum TcpEstablishedError: Error
{
    case missingStraws
}
