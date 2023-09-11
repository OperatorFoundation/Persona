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
        let clientWindow = self.straw.clientWindow(size: tcp.windowSize)
        let packetLowerBound = SequenceNumber(tcp.sequenceNumber)
        var packetUpperBound = packetLowerBound
        
        /// If the TCP is in one of the synchronized states (ESTABLISHED, FIN-WAIT-1, FIN-WAIT-2, CLOSE-WAIT, CLOSING, LAST-ACK, TIME-WAIT),
        /// it aborts the connection and informs its user.
        if tcp.rst
        {
            return try await handleRstSynchronizedState(ipv4: ipv4, tcp: tcp)
        }
        
        /// If the connection is in a synchronized state (ESTABLISHED, FIN-WAIT-1, FIN-WAIT-2, CLOSE-WAIT, CLOSING, LAST-ACK, TIME-WAIT),
        /// any unacceptable segment (out of window sequence number or unacceptable acknowledgment number) must elicit only an empty
        /// acknowledgment segment containing the current send-sequence number and an acknowledgment indicating the next sequence number expected
        /// to be received, and the connection remains in the same state.
        
        guard self.straw.inWindow(tcp) else
        {
            self.logger.error("❌ TcpFinWait2 - \(clientWindow.lowerBound) <= \(packetLowerBound)..<\(packetUpperBound) <= \(clientWindow.upperBound)")

            let ack = try await self.makeAck()
            return TcpStateTransition(newState: self, packetsToSend: [ack])
        }
        
        guard tcp.fin else
        {
            // TODO: Log this
            return TcpStateTransition(newState: self)
        }

        // FIXME: TIME WAIT should be the next state
        let ack = try await makeAck()
        return TcpStateTransition(newState: TcpClosed(self), packetsToSend: [ack])
    }
}

public enum TcpFinWait2Error: Error
{
}
