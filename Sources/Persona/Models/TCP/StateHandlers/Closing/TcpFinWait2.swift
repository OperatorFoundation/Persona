//
//  TcpFinWait2.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/6/23.
//

import Foundation

import Foundation

import InternetProtocols

// FIXME: implement this state

/// FIN-WAIT-2 - represents waiting for a connection termination request from the remote TCP.
public class TcpFinWait2: TcpStateHandler
{
    public override func processDownstreamPacket(ipv4: IPv4, tcp: TCP, payload: Data?) async throws -> TcpStateTransition
    {
        /// If the connection is in a synchronized state (ESTABLISHED, FIN-WAIT-1, FIN-WAIT-2, CLOSE-WAIT, CLOSING, LAST-ACK, TIME-WAIT),
        /// any unacceptable segment (out of window sequence number or unacceptable acknowledgment number) must elicit only an empty
        /// acknowledgment segment containing the current send-sequence number and an acknowledgment indicating the next sequence number expected
        /// to be received, and the connection remains in the same state.
        
        guard try await acceptableSegment(upstreamStraw: self.upstreamStraw, tcp: tcp) else
        {
            let seqNum = await upstreamStraw?.sequenceNumber()
            self.logger.log(level: .debug, "TCPFinWait2 processDownstreamPacket received an ACK with acknowledgement number (\(SequenceNumber(tcp.acknowledgementNumber))) that does not match our last sequence number (\(String(describing: seqNum))). Re-sending previous ack")
            
            let ack = try await makeAck()
            return TcpStateTransition(newState: self, packetsToSend: [ack])
        }
        
        if tcp.fin
        {
            // FIXME: TIME WAIT should be the next state
            let ack = try await makeAck()
            return TcpStateTransition(newState: TcpClosed(self), packetsToSend: [ack])
        }
        
        /**
         If the TCP is in one of the synchronized states (ESTABLISHED,
         FIN-WAIT-1, FIN-WAIT-2, CLOSE-WAIT, CLOSING, LAST-ACK, TIME-WAIT), it
         aborts the connection and informs its user.  We discuss this latter
         case under "half-open" connections below.
         */
        if tcp.rst
        {
            // FIXME: Abort the connection and inform the user
            return TcpStateTransition(newState: TcpClosing(self))
        }
        
        // FIXME: Other tcp flags
        return TcpStateTransition(newState: self)
    }
}

public enum TcpFinWait2Error: Error
{
}
