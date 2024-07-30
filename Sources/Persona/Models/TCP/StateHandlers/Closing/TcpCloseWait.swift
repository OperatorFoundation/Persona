//
//  TcpCloseWait.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/6/23.
//

import Foundation

import InternetProtocols

/// CLOSE-WAIT - represents waiting for a connection termination request  the local user.
///
/// CLOSE-WAIT means we have received a FIN from the client.
/// No more data will be arriving from the client.
/// Upon transitioning to CLOSE-WAIT, we close the connection to the upstream server, so there will be no more data from the server.
/// We will keep checking on if there is more data from the server
///
public class TcpCloseWait: TcpStateHandler
{
    override public func processDownstreamPacket(stats: Stats, ipv4: IPv4, tcp: TCP, payload: Data?) async throws -> TcpStateTransition
    {
        stats.closeWait = stats.closeWait + 1

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
            let ack = try await makeAck(stats: stats)
            packetsToSend.append(ack)
        }

        if self.retransmissionQueue.isEmpty
        {
            let lastAck = TcpLastAck(self)
            return TcpStateTransition(newState: lastAck, packetsToSend: packetsToSend)
        }
        else
        {
            // We received something after receiving a FIN, do nothing
            return TcpStateTransition(newState: self, packetsToSend: packetsToSend)
        }
    }
}

