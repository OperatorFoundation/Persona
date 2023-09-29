//
//  TcpFinWait1.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/5/23.
//

import Foundation

import InternetProtocols

/**
 FIN-WAIT-1 - represents waiting for a connection termination request
 from the remote TCP, or an acknowledgment of the connection
 termination request previously sent.
 
 Case 1:  Local user initiates the close

   In this case, a FIN segment can be constructed and placed on the
   outgoing segment queue.  No further SENDs from the user will be
   accepted by the TCP, and it enters the FIN-WAIT-1 state.  RECEIVEs
   are allowed in this state.  All segments preceding and including FIN
   will be retransmitted until acknowledged.  When the other TCP has
   both acknowledged the FIN and sent a FIN of its own, the first TCP
   can ACK this FIN.  Note that a TCP receiving a FIN will ACK but not
   send its own FIN until its user has CLOSED the connection also.
 */

public class TcpFinWait1: TcpStateHandler
{
    override public func processDownstreamPacket(stats: Stats, ipv4: IPv4, tcp: TCP, payload: Data?) async throws -> TcpStateTransition
    {
        stats.finWait1 = stats.finWait1 + 1

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
            self.logger.error("❌ TcpFinWait1 - \(clientWindow.lowerBound) <= \(packetLowerBound)..<\(packetUpperBound) <= \(clientWindow.upperBound)")

            let ack = try await self.makeAck(stats: stats)
            return TcpStateTransition(newState: self, packetsToSend: [ack])
        }

        if tcp.ack
        {
            let acknowledgementNumber = SequenceNumber(tcp.acknowledgementNumber)
            self.logger.debug("TcpFinWait1.processDownstreamPacket - received an ACK")
            self.logger.debug(" acknowledgement number: \(acknowledgementNumber)")
            self.logger.debug(" straw.sequenceNumber: \(self.straw.sequenceNumber)")
            
            if tcp.fin
            {
                /**
                If the FIN bit is set, signal the user "connection closing" and return any pending RECEIVEs with same message,
                advance RCV.NXT over the FIN, and send an acknowledgment for the FIN.
                Note that FIN implies PUSH for any segment text not yet delivered to the user.
                
                FIN-WAIT-1 STATE
                If our FIN has been ACKed (perhaps in this segment), then
                enter TIME-WAIT, start the time-wait timer, turn off the other
                timers; otherwise enter the CLOSING state.
                */
                
                let ack = try await makeAck(stats: stats)
                return TcpStateTransition(newState: TcpClosing(self), packetsToSend: [ack])
            }
            else
            {
                return TcpStateTransition(newState: TcpFinWait2(self))
            }
        }
        
        return TcpStateTransition(newState: self)
    }
    
    override public func processUpstreamData(stats: Stats, data: Data) async throws -> TcpStateTransition 
    {
        // FIN WAIT-1: We have already sent a FIN downstream, No further SENDs will be accepted by the TCP
        self.logger.debug("TcpFinWait1.processUpstreamData - received upstream data, ignoring.")
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
        self.logger.debug("TcpFinWait1.processUpstreamClose - Upstream closed called when a CLOSE has already been received.")
        return TcpStateTransition(newState: self)
    }
}

public enum TcpFinWait1Error: Error
{
}
