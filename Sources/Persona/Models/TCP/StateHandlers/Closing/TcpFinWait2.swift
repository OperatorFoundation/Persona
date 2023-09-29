//
//  TcpFinWait2.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/6/23.
//

import Foundation

import InternetProtocols

/// FIN-WAIT-2 - represents waiting for a connection termination request from the remote TCP.
/// 
public class TcpFinWait2: TcpStateHandler
{
    public override func processDownstreamPacket(stats: Stats, ipv4: IPv4, tcp: TCP, payload: Data?) async throws -> TcpStateTransition
    {
        stats.finWait2 = stats.finWait2 + 1

        let clientWindow = self.straw.clientWindow(size: tcp.windowSize)
        let packetLowerBound = SequenceNumber(tcp.sequenceNumber)
        let packetUpperBound = packetLowerBound
        
        /// If the TCP is in one of the synchronized states (ESTABLISHED, FIN-WAIT-1, FIN-WAIT-2, CLOSE-WAIT, CLOSING, LAST-ACK, TIME-WAIT),
        /// it aborts the connection and informs its user.
        if tcp.rst
        {
            return try await handleRstSynchronizedState(stats: stats, ipv4: ipv4, tcp: tcp)
        }
        
        /// If the connection is in a synchronized state (ESTABLISHED, FIN-WAIT-1, FIN-WAIT-2, CLOSE-WAIT, CLOSING, LAST-ACK, TIME-WAIT),
        /// any unacceptable segment (out of window sequence number or unacceptable acknowledgment number) must elicit only an empty
        /// acknowledgment segment containing the current send-sequence number and an acknowledgment indicating the next sequence number expected
        /// to be received, and the connection remains in the same state.
        
        guard self.straw.inWindow(tcp) else
        {
            self.logger.error("❌ TcpFinWait2 - \(clientWindow.lowerBound) <= \(packetLowerBound)..<\(packetUpperBound) <= \(clientWindow.upperBound)")

            let ack = try await self.makeAck(stats: stats)
            return TcpStateTransition(newState: self, packetsToSend: [ack])
        }
        
        guard tcp.fin else
        {
            let acknowledgementNumber = SequenceNumber(tcp.acknowledgementNumber)
            self.logger.debug("TcpFinWait2.processDownstreamPacket - received a packet other than FIN or RST")
            self.logger.debug(" acknowledgement number: \(acknowledgementNumber)")
            self.logger.debug(" straw.sequenceNumber: \(self.straw.sequenceNumber)")
            
            return TcpStateTransition(newState: self)
        }

        // FIXME: TIME WAIT should be the next state
        let ack = try await makeAck(stats: stats)
        return TcpStateTransition(newState: TcpClosed(self), packetsToSend: [ack])
    }
    
    override public func processUpstreamData(stats: Stats, data: Data) async throws -> TcpStateTransition
    {
        // FIN WAIT-2: We have already sent a FIN downstream, No further SENDs will be accepted by the TCP
        self.logger.debug("TcpFinWait2.processUpstreamData - received upstream data, ignoring.")
        return TcpStateTransition(newState: self)
    }
    
    override public func processUpstreamClose(stats: Stats) async throws -> TcpStateTransition
    {
        /**
        Strictly speaking, this is an error and should receive a "error:
        connection closing" response.  An "ok" response would be
        acceptable, too, as long as a second FIN is not emitted (the first
        FIN may be retransmitted though).
         */
        self.logger.debug("TcpFinWait2.processUpstreamClose - Upstream closed called when a CLOSE has already been received.")
        return TcpStateTransition(newState: self)
    }
}

public enum TcpFinWait2Error: Error
{
}
