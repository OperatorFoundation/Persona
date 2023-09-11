//
//  TcpCloseWait.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/6/23.
//

import Foundation

import InternetProtocols

// CLOSE-WAIT means we have received a FIN from the client.
// No more data will be arriving from the client.
// We will keep checking on if there is more data from the server as
public class TcpCloseWait: TcpStateHandler
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

        /**
         If the TCP is in one of the synchronized states (ESTABLISHED,
         FIN-WAIT-1, FIN-WAIT-2, CLOSE-WAIT, CLOSING, LAST-ACK, TIME-WAIT), it
         aborts the connection and informs its user.  We discuss this latter
         case under "half-open" connections below.
         */
        if tcp.syn || tcp.rst
        {
            return try await handleRstSynchronizedState(ipv4: ipv4, tcp: tcp)
        }

        /// If the connection is in a synchronized state (ESTABLISHED, FIN-WAIT-1, FIN-WAIT-2, CLOSE-WAIT, CLOSING, LAST-ACK, TIME-WAIT),
        /// any unacceptable segment (out of window sequence number or unacceptable acknowledgment number) must elicit only an empty
        /// acknowledgment segment containing the current send-sequence number and an acknowledgment indicating the next sequence number expected
        /// to be received, and the connection remains in the same state.
        
        guard self.straw.inWindow(tcp) else
        {
            self.logger.error("❌ TcpCloseWait - \(clientWindow.lowerBound) <= \(packetLowerBound)..<\(packetUpperBound) <= \(clientWindow.upperBound)")

            let ack = try await self.makeAck()
            return TcpStateTransition(newState: self, packetsToSend: [ack])
        }

        self.logger.error("✅ TcpCloseWait - \(clientWindow.lowerBound) <= \(packetLowerBound)..<\(packetUpperBound) <= \(clientWindow.upperBound)")

        if tcp.ack
        {
            let acknowledgementNumber = SequenceNumber(tcp.acknowledgementNumber)

            if acknowledgementNumber != self.straw.sequenceNumber
            {
                try self.straw.acknowledge(acknowledgementNumber)
            }
        }

        let serverIsStillOpen: Bool = await self.pumpServerToStraw()
        var packets = try await self.pumpStrawToClient(tcp)

        if serverIsStillOpen
        {
            try await self.upstream.close()
        }

        // Send FIN
        let fin = try await makeFin()
        packets.append(fin)

        return TcpStateTransition(newState: TcpLastAck(self), packetsToSend: packets)
    }
}

public enum TcpCloseWaitError: Error
{
}
