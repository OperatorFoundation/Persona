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
        guard let upstreamStraw = self.upstreamStraw else
        {
            throw TcpEstablishedError.missingStraws
        }

        let upstreamWindow = await upstreamStraw.window
        let packetLowerBound = SequenceNumber(tcp.sequenceNumber)
        let packetUpperBound = packetLowerBound.add(Int(tcp.windowSize))

        // We can only receive data inside the TCP window.
        guard await upstreamStraw.inWindow(tcp) else
        {
            self.logger.error("❌ \(upstreamWindow.lowerBound) <= \(packetLowerBound)..<\(packetUpperBound) <= \(upstreamWindow.upperBound)")

            let sequenceNumber = await upstreamStraw.sequenceNumber()
            let acknowledgementNumber = await upstreamStraw.acknowledgementNumber()
            let windowSize = await upstreamStraw.windowSize()
            
            // Send an ACK to let the client know that they are outside of the TCP window.
            let ack = try self.makePacket(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize, ack: true)
            return TcpStateTransition(newState: self, packetsToSend: [ack])
        }

        self.logger.error("✅ \(upstreamWindow.lowerBound) <= \(packetLowerBound)..<\(packetUpperBound) <= \(upstreamWindow.upperBound)")

//        self.logger.debug("TcpEstablished.processDownstreamPacket")
        /*
         Once in the ESTABLISHED state, it is possible to deliver segment
         text to user RECEIVE buffers.  Text from segments can be moved
         into buffers until either the buffer is full or the segment is
         empty.  If the segment empties and carries an PUSH flag, then
         the user is informed, when the buffer is returned, that a PUSH
         has been received.
         */

        if let _ = tcp.payload
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
            try await upstreamStraw.write(tcp)

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
            let sequenceNumber = await upstreamStraw.sequenceNumber()
            let acknowledgementNumber = await upstreamStraw.acknowledgementNumber()
            let windowSize = await upstreamStraw.windowSize()
            let ack = try self.makePacket(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize, ack: true)
            return TcpStateTransition(newState: self, packetsToSend: [ack])
        }

        if tcp.ack
        {
            // FIXME - adjust windowSize based on ACK
        }

        if tcp.rst
        {
            // FIXME - reset connection
        }

        if tcp.fin
        {
            // FIXME -s tart closing connection
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
}

public enum TcpEstablishedError: Error
{
    case missingStraws
}
