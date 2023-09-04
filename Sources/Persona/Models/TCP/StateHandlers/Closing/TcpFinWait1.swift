//
//  TcpFinWait1.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/5/23.
//

import Foundation

import InternetProtocols

/**
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
            self.logger.log(level: .debug, "TCPFinWait1 processDownstreamPacket received an ACK with acknowledgement number (\(SequenceNumber(tcp.acknowledgementNumber))) that does not match our last sequence number (\(String(describing: seqNum))). Re-sending previous ack")
            
            let ack = try await makeAck()
            return TcpStateTransition(newState: self, packetsToSend: [ack])
        }
        
        if tcp.fin
        {
            let ack = try await makeAck()
            return TcpStateTransition(newState: TcpClosing(self), packetsToSend: [ack])
        }
        
        guard tcp.ack else
        {
            // TODO: Log this
            return TcpStateTransition(newState: self)
        }
        
        return TcpStateTransition(newState: TcpFinWait2(self))
    }
}

public enum TcpFinWait1Error: Error
{
}
