//
//  TcpLaskAck.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/6/23.
//

import Foundation

import InternetProtocols

public class TcpLastAck: TcpStateHandler
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
        
        guard self.straw.inWindow(tcp) else
        {
            let seqNum = self.straw.sequenceNumber
            self.logger.log(level: .debug, "TCPLastAck processDownstreamPacket received an ACK with acknowledgement number (\(SequenceNumber(tcp.acknowledgementNumber))) that does not match our last sequence number (\(String(describing: seqNum))). Re-sending previous ack")
            
            /// If the connection is in a synchronized state (ESTABLISHED, FIN-WAIT-1, FIN-WAIT-2, CLOSE-WAIT, CLOSING, LAST-ACK, TIME-WAIT),
            /// any unacceptable segment (out of window sequence number or unacceptable acknowledgment number) must elicit only an empty
            /// acknowledgment segment containing the current send-sequence number and an acknowledgment indicating the next sequence number expected
            /// to be received, and the connection remains in the same state.
            
            let ack = try await makeAck()
            return TcpStateTransition(newState: self, packetsToSend: [ack])
        }
        
        guard tcp.ack else
        {
            // TODO: Log this
            return TcpStateTransition(newState: self)
        }
        
        return TcpStateTransition(newState: TcpClosed(self))
    }
}

public enum TcpLastAckError: Error
{
}
