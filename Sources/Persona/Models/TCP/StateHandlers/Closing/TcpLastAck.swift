//
//  TcpLaskAck.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/6/23.
//

import Foundation

import InternetProtocols

/// LAST-ACK - represents waiting for an acknowledgment of the connection termination request previously sent to the remote TCP
/// (which includes an acknowledgment of its connection termination request).
///
public class TcpLastAck: TcpStateHandler
{
    override public func processDownstreamPacket(stats: Stats, ipv4: IPv4, tcp: TCP, payload: Data?) async throws -> TcpStateTransition
    {
        stats.lastAck = stats.lastAck + 1

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
            self.logger.error("❌ TcpLastAck - \(clientWindow.lowerBound) <= \(packetLowerBound)..<\(packetUpperBound) <= \(clientWindow.upperBound)")

            let ack = try await self.makeAck(stats: stats)
            return TcpStateTransition(newState: self, packetsToSend: [ack])
        }
        
        guard tcp.ack else
        {
            let acknowledgementNumber = SequenceNumber(tcp.acknowledgementNumber)
            self.logger.debug("TcpLastAck.processDownstreamPacket - received something other than ACK")
            self.logger.debug(" acknowledgement number: \(acknowledgementNumber)")
            self.logger.debug(" straw.sequenceNumber: \(self.straw.sequenceNumber)")
            
            return TcpStateTransition(newState: self)
        }

        // The incoming packet during LastAck should be one more than what we use on outgoing packets.
        // This is because we already sent a FIN, which incremented the sequence number by 1.
        // However, in LastAck we ONLY send rebroadcasts of the FIN.
        // These use the previous sequence number, because they are rebroadcasts.
        // So rather than incrementing the SEQ# each time we send and then rolling it back each time we rebroadcast,
        // we will just leave it and check that the incoming ACK# is our recorded SEQ# + 1.
        let (sequenceNumber, _, _) = self.getState()
        guard SequenceNumber(tcp.acknowledgementNumber) == sequenceNumber.increment() else
        {
            self.logger.debug("TcpLastAck.processDownstreamPacket - received an ACK with an acknowledgement number that does not match our FIN sequence number. Rebroadcasting our FIN.")
            self.logger.debug(" acknowledgement number: \(SequenceNumber(tcp.acknowledgementNumber))")
            self.logger.debug(" should be: \(sequenceNumber) + 1")
            
            let fin = try await self.makeFinAck()

            return TcpStateTransition(newState: self, packetsToSend: [fin])
        }

        return TcpStateTransition(newState: TcpClosed(self))
    }
    
    override public func processUpstreamData(stats: Stats, data: Data) async throws -> TcpStateTransition
    {
        // LAST-ACK: We have already told downstream we would not send anymore data
        self.logger.debug("TcpLastAck.processUpstreamData - received upstream data, we've already sent a FIN downstream, ignoring.")
        return TcpStateTransition(newState: self)
    }
    
    override public func processUpstreamClose(stats: Stats) async throws -> TcpStateTransition
    {
        /**
        CLOSE Call - LAST-ACK STATE
        Respond with "error:  connection closing".
         */
        
        self.logger.debug("TcpLastAck.processUpstreamClose - Upstream closed called when a CLOSE has already been received (this is considered an error).")
        return TcpStateTransition(newState: self)
    }
}

public enum TcpLastAckError: Error
{
}
