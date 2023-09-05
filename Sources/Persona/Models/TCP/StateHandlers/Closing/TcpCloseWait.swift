//
//  TcpCloseWait.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/6/23.
//

import Foundation

import InternetProtocols

// FIXME me - implement this state
public class TcpCloseWait: TcpStateHandler
{
    override public func processDownstreamPacket(ipv4: IPv4, tcp: TCP, payload: Data?) async throws -> TcpStateTransition
    {
        /**
         If the TCP is in one of the synchronized states (ESTABLISHED,
         FIN-WAIT-1, FIN-WAIT-2, CLOSE-WAIT, CLOSING, LAST-ACK, TIME-WAIT), it
         aborts the connection and informs its user.  We discuss this latter
         case under "half-open" connections below.
         */
        if tcp.rst
        {
            // FIXME: Abort the connection and inform the user
            return TcpStateTransition(newState: TcpClosed(self))
        }
        /// If the connection is in a synchronized state (ESTABLISHED, FIN-WAIT-1, FIN-WAIT-2, CLOSE-WAIT, CLOSING, LAST-ACK, TIME-WAIT),
        /// any unacceptable segment (out of window sequence number or unacceptable acknowledgment number) must elicit only an empty
        /// acknowledgment segment containing the current send-sequence number and an acknowledgment indicating the next sequence number expected
        /// to be received, and the connection remains in the same state.
        
        guard self.straw.inWindow(tcp) else
        {
            let seqNum = self.straw.sequenceNumber
            self.logger.log(level: .debug, "TCPFinWait2 processDownstreamPacket received an ACK with acknowledgement number (\(SequenceNumber(tcp.acknowledgementNumber))) that does not match our last sequence number (\(String(describing: seqNum))). Re-sending previous ack")
            
            let ack = try await makeAck()
            return TcpStateTransition(newState: self, packetsToSend: [ack])
        }
        
        guard tcp.ack else
        {
            return TcpStateTransition(newState: self)
        }
        
        var packets = try await pumpServerToClient(tcp)

        return TcpStateTransition(newState: TcpLastAck(self), packetsToSend: packets)
    }
    
    func pumpServerToClient(_ tcp: TCP) async throws -> [IPv4]
    {
        // Buffer data from the server until the client ACKs it.
        let data = try await self.upstream.read()

        if data.count > 0
        {
            try self.straw.write(data)
            self.logger.info("TcpCloseWait.pumpServerToClient: Persona <-- tcpproxy - \(data.count) bytes")
        }

        if !self.straw.isEmpty
        {
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
            
            // CLOSE-WAIT should send a fin after the buffer has been sent along or alone if there is nothing in the buffer
            let window = SequenceNumberRange(lowerBound: nextSequenceNumber, size: 1)
            let fin = try await makeFin(window: window)
            packets.append(fin)
            
            return packets
        }
        else
        {
            // CLOSE-WAIT should send a fin after the buffer has been sent along or alone if there is nothing in the buffer
            let fin = try await makeFin()
            return [fin]
        }
    }
}

public enum TcpCloseWaitError: Error
{
}
