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

        /// If the TCP is in one of the synchronized states (ESTABLISHED, FIN-WAIT-1, FIN-WAIT-2, CLOSE-WAIT, CLOSING, LAST-ACK, TIME-WAIT),
        /// it aborts the connection and informs its user.
        if tcp.rst
        {
            return try await handleRstSynchronizedState(stats: stats, ipv4: ipv4, tcp: tcp)
        }

        if tcp.ack
        {
            #if DEBUG
            self.logger.debug("👋 New ACK# Received - \(tcp.acknowledgementNumber)")
            #endif

            let acknowledgementNumber = SequenceNumber(tcp.acknowledgementNumber)

            #if DEBUG
            self.logger.debug("Retransmission queue has \(self.retransmissionQueue.count) segments before ACK")
            #endif

            self.retransmissionQueue.acknowledge(acknowledgementNumber: acknowledgementNumber)

            #if DEBUG
            self.logger.debug("Retransmission queue has \(self.retransmissionQueue.count) segments after ACK")
            #endif
        }

        var packetsToSend: [IPv4] = []

        if tcp.fin // We received the FIN again, re-send our ACK
        {
            // The incoming packet during LastAck should be one more than what we use on outgoing packets.
            // This is because we already sent a FIN, which incremented the sequence number by 1.
            // However, in LastAck we ONLY send rebroadcasts of the FIN.
            // These use the previous sequence number, because they are rebroadcasts.
            // So rather than incrementing the SEQ# each time we send and then rolling it back each time we rebroadcast,
            // we will just leave it and check that the incoming ACK# is our recorded SEQ# + 1.
            let ack = try await makeAck(stats: stats)
            packetsToSend.append(ack)
        }

        if self.retransmissionQueue.isEmpty
        {
            let lastAck = TcpClosed(self)
            return TcpStateTransition(newState: lastAck, packetsToSend: packetsToSend)
        }
        else
        {
            // We received something after receiving a FIN, do nothing
            return TcpStateTransition(newState: self, packetsToSend: packetsToSend)
        }
    }
}

public enum TcpLastAckError: Error
{
}
