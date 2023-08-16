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
        self.logger.debug("TcpSynReceived.processDownstreamPacket: \(identity.localAddress.data.ipv4AddressString ?? "?.?.?.?"):\(identity.localPort) -> \(identity.remoteAddress.data.ipv4AddressString ?? "?.?.?.?"):\(identity.remotePort)")
        if identity.remotePort == 7 || identity.remotePort == 853
        {
            self.tcpLogger.debug("TcpSynReceived.procesDownstreamPacket: \(identity.localAddress.data.ipv4AddressString ?? "?.?.?.?"):\(identity.localPort) -> \(identity.remoteAddress.data.ipv4AddressString ?? "?.?.?.?"):\(identity.remotePort)")
        }

        // We should not be receiving a RST.
        guard !tcp.rst else
        {
            self.logger.debug("TcpSynReceived: rejected packet because of RST")
            if identity.remotePort == 7 || identity.remotePort == 853
            {
                self.tcpLogger.debug("TcpSynReceived: rejected packet because of RST")
            }

            return try self.panicOnDownstream(ipv4: ipv4, tcp: tcp, payload: payload)
        }

        // We should not be receiving a FIN.
        guard !tcp.fin else
        {
            self.logger.debug("TcpSynReceived: rejected packet because of FIN")
            if identity.remotePort == 7 || identity.remotePort == 853
            {
                self.tcpLogger.debug("TcpSynReceived: rejected packet because of FIN")
            }

            return try self.panicOnDownstream(ipv4: ipv4, tcp: tcp, payload: payload)
        }

        // In the SYN-RECEIVED state, we may received duplicate SYNs, but new SYNs are not allowed.
        if tcp.syn
        {
            let newSequenceNumber = SequenceNumber(tcp.sequenceNumber)
            self.tcpLogger.info("duplicate SYN \(newSequenceNumber) \(self.downstreamStraw.sequenceNumber), using new SYN")

            // SYN gives us a sequence number, so reset the straw sequence number
            self.downstreamStraw = TCPDownstreamStraw(segmentStart: self.downstreamStraw.sequenceNumber, windowSize: tcp.windowSize)
            self.upstreamStraw = TCPUpstreamStraw(segmentStart: SequenceNumber(tcp.sequenceNumber))

            self.logger.debug("TcpSynReceived: staying in SYN-RECEIVED, using new SYN, sending new SYN-ACK")
            if identity.remotePort == 7 || identity.remotePort == 853
            {
                self.tcpLogger.debug("TcpSynReceived: staying in SYN-RECEIVED, using new SYN, sending new SYN-ACK")
            }

            // Send a SYN-ACK for the new SYN
            let synAck = try self.makeSynAck()
            return TcpStateTransition(newState: self, packetsToSend: [synAck])
        }

        // We expect to receive an ACK.
        guard tcp.ack else
        {
            self.logger.debug("TcpSynReceived: ACK received, transitioning to ESTABLISHED, no packets to send")
            if identity.remotePort == 7 || identity.remotePort == 853
            {
                self.tcpLogger.debug("TcpSynReceived: ACK received, transitioning to ESTABLISHED, no packets to send")
            }

            // They must not have heard our SYN-ACK, resend it.
            self.logger.debug("TcpSynReceived: staying in SYN-RECEIVED, resending SYN-ACK")
            if identity.remotePort == 7 || identity.remotePort == 853
            {
                self.tcpLogger.debug("TcpSynReceived: staying in SYN-RECEIVED, resending SYN-ACK")
            }

            let synAck = try self.makeSynAck()
            return TcpStateTransition(newState: self, packetsToSend: [synAck])
        }

        // We have an ACK for our SYN-ACK. Change to ESTABLISHED state.
        return TcpStateTransition(newState: TcpEstablished(self))
    }

    func makeSynAck() throws -> IPv4
    {
        return try self.makePacket(sequenceNumber: self.downstreamStraw.sequenceNumber, acknowledgementNumber: self.upstreamStraw.acknowledgementNumber, syn: true, ack: true)
    }
}

public enum TcpSynReceivedError: Error
{
}
