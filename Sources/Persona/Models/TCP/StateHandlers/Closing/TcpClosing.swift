//
//  TcpClosing.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/6/23.
//

import Foundation

import InternetProtocols

/// CLOSING - represents waiting for a connection termination request acknowledgment from the remote TCP.
/// 
public class TcpClosing: TcpStateHandler
{
    override public func processDownstreamPacket(stats: Stats, ipv4: IPv4, tcp: TCP, payload: Data?) async throws -> TcpStateTransition
    {
        stats.closing = stats.closing + 1

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
            self.logger.error("❌ TcpClosing - \(clientWindow.lowerBound) <= \(packetLowerBound)..<\(packetUpperBound) <= \(clientWindow.upperBound)")

            let ack = try await self.makeAck(stats: stats)
            return TcpStateTransition(newState: self, packetsToSend: [ack])
        }
        
        guard tcp.ack else
        {
            let acknowledgementNumber = SequenceNumber(tcp.acknowledgementNumber)
            self.logger.debug("TcpClosing.processDownstreamPacket - did not receive an ACK")
            self.logger.debug(" acknowledgement number: \(acknowledgementNumber)")
            self.logger.debug(" straw.sequenceNumber: \(self.straw.sequenceNumber)")
            
            return TcpStateTransition(newState: self)
        }
        
        // We are expecting an ack so everything is proceeding according to plan!
        return TcpStateTransition(newState: TcpClosed(self))
    }
    
    override public func processUpstreamData(stats: Stats, data: Data) async throws -> TcpStateTransition
    {
        // We have already sent a FIN downstream, No further SENDs will be accepted by the TCP
        self.logger.debug("TcpClosing.processUpstreamData - received upstream data, ignoring.")
        return TcpStateTransition(newState: self)
    }
    
    override public func processUpstreamClose(stats: Stats) async throws -> TcpStateTransition
    {
        /**
        CLOSE Call - CLOSING State
        Respond with "error:  connection closing".
         */
        
        self.logger.debug("TcpClosing.processUpstreamClose - Upstream closed called when a CLOSE has already been received (this is considered an error).")
        return TcpStateTransition(newState: self)
    }
}

public enum TcpClosingError: Error
{
}
