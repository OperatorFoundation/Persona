//
//  TcpClosing.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/6/23.
//

import Foundation

import InternetProtocols

// FIXME me - implement this state
public class TcpClosing: TcpStateHandler
{
    override public func processDownstreamPacket(ipv4: IPv4, tcp: TCP, payload: Data?) async throws -> TcpStateTransition
    {
        let clientWindow = self.straw.clientWindow(size: tcp.windowSize)
        let packetLowerBound = SequenceNumber(tcp.sequenceNumber)
        let packetUpperBound = packetLowerBound
        
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
            self.logger.error("❌ TcpClosing - \(clientWindow.lowerBound) <= \(packetLowerBound)..<\(packetUpperBound) <= \(clientWindow.upperBound)")

            let ack = try await self.makeAck()
            return TcpStateTransition(newState: self, packetsToSend: [ack])
        }
        
        guard tcp.ack else
        {
            let acknowledgementNumber = SequenceNumber(tcp.acknowledgementNumber)
            self.logger.debug("TcpClosing.processDownstreamPacket - received an ACK")
            self.logger.debug(" acknowledgement number: \(acknowledgementNumber)")
            self.logger.debug(" straw.sequenceNumber: \(self.straw.sequenceNumber)")
            
            return TcpStateTransition(newState: self)
        }
        
        // We are expecting an ack so everything is proceeding according to plan!
        // FIXME: We should be going to TIME WAIT before closed
        return TcpStateTransition(newState: TcpClosed(self))
    }
}

public enum TcpClosingError: Error
{
}
