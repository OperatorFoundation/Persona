//
//  TcpSynReceived.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/5/23.
//

import Foundation

import InternetProtocols

public class TcpSynReceived: TcpStateHandler
{
    override public func processDownstreamPacket(ipv4: IPv4, tcp: TCP, payload: Data?) throws -> TcpStateTransition
    {
        // We should not be receiving a RST.
        guard !tcp.rst else
        {
            return try self.panicOnDownstream(ipv4: ipv4, tcp: tcp, payload: payload)
        }

        // We should not be receiving a FIN.
        guard !tcp.fin else
        {
            return try self.panicOnDownstream(ipv4: ipv4, tcp: tcp, payload: payload)
        }

        // In the SYN-RECEIVED state, we may received duplicate SYNs, but new SYNs are not allowed.
        if tcp.syn
        {
            let newSequenceNumber = SequenceNumber(tcp.sequenceNumber)
            self.tcpLogger.info("duplicate SYN \(newSequenceNumber) \(self.downstreamStraw.sequenceNumber)")

            // We ignore duplicate SYNs.
            return TcpStateTransition(newState: self)
        }

        // We expect to receive an ACK.
        guard tcp.ack else
        {
            // They must not have received our SYN-ACK, resend it.
            let synAck = try self.makeSynAck()
            return TcpStateTransition(newState: self, packetsToSend: [synAck])
        }

        // We have an ACK for our SYN-ACK. Change to ESTABLISHED state.
        let newState = TcpEstablished(self)
        return TcpStateTransition(newState: newState)
    }

    func makeSynAck() throws -> IPv4
    {
        return try self.makePacket(sequenceNumber: self.downstreamStraw.sequenceNumber, acknowledgementNumber: self.upstreamStraw.acknowledgementNumber, syn: true, ack: true)
    }
}

public enum TcpSynReceivedError: Error
{
}
