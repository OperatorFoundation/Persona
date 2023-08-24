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
    override public var description: String
    {
        return "[TcpSynReceived]"
    }

    override public func processDownstreamPacket(ipv4: IPv4, tcp: TCP, payload: Data?) async throws -> TcpStateTransition
    {
        guard let upstreamStraw = self.upstreamStraw, let downstreamStraw = self.downstreamStraw else
        {
            throw TcpEstablishedError.missingStraws
        }

        self.logger.debug("TcpSynReceived.processDownstreamPacket: \(identity.localAddress.data.ipv4AddressString ?? "?.?.?.?"):\(identity.localPort) -> \(identity.remoteAddress.data.ipv4AddressString ?? "?.?.?.?"):\(identity.remotePort)")
        if identity.remotePort == 7 || identity.remotePort == 853
        {
            self.tcpLogger.debug("TcpSynReceived.procesDownstreamPacket: \(identity.localAddress.data.ipv4AddressString ?? "?.?.?.?"):\(identity.localPort) -> \(identity.remoteAddress.data.ipv4AddressString ?? "?.?.?.?"):\(identity.remotePort)")
        }

        // We should not be receiving a RST.
        guard !tcp.rst else
        {
            self.logger.trace("-> TcpSynReceived.RST: \(ipv4.sourceAddress.ipv4AddressString ?? "?.?.?.?."):\(tcp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "?.?.?.?.") - RST:\(tcp.rst), SEQ#:\(SequenceNumber(tcp.sequenceNumber)), ACK#:\(SequenceNumber(tcp.acknowledgementNumber)), CHK:\(tcp.checksum).data.hex")

            self.logger.debug("TcpSynReceived: rejected packet because of RST")
            if identity.remotePort == 7 || identity.remotePort == 853
            {
                self.tcpLogger.debug("TcpSynReceived: rejected packet because of RST")
            }

            let sequenceNumber = await downstreamStraw.sequenceNumber()
            let acknowledgementNumber = await upstreamStraw.acknowledgementNumber()
            let windowSize = await downstreamStraw.windowSize()
            return try await self.panicOnDownstream(ipv4: ipv4, tcp: tcp, payload: payload, sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize)
        }

        // We should not be receiving a FIN.
        guard !tcp.fin else
        {
            self.logger.trace("-> TcpSynReceived.FIN: \(ipv4.sourceAddress.ipv4AddressString ?? "?.?.?.?."):\(tcp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "?.?.?.?.") - FIN:\(tcp.fin), SEQ#:\(SequenceNumber(tcp.sequenceNumber)), ACK#:\(SequenceNumber(tcp.acknowledgementNumber)), CHK:\(tcp.checksum).data.hex")

            self.logger.debug("TcpSynReceived: rejected packet because of FIN")
            if identity.remotePort == 7 || identity.remotePort == 853
            {
                self.tcpLogger.debug("TcpSynReceived: rejected packet because of FIN")
            }

            let sequenceNumber = await downstreamStraw.sequenceNumber()
            let acknowledgementNumber = await upstreamStraw.acknowledgementNumber()
            let windowSize = await downstreamStraw.windowSize()
            return try await self.panicOnDownstream(ipv4: ipv4, tcp: tcp, payload: payload, sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize)
       }

        // In the SYN-RECEIVED state, we may received duplicate SYNs, but new SYNs are not allowed.
        if tcp.syn
        {
            let newSequenceNumber = SequenceNumber(tcp.sequenceNumber)
            let oldSequenceNumber = await downstreamStraw.sequenceNumber()
            self.tcpLogger.info("duplicate SYN \(newSequenceNumber) \(oldSequenceNumber), using new SYN")
            self.logger.trace("-> TcpSynReceived.SYN: \(ipv4.sourceAddress.ipv4AddressString ?? "?.?.?.?."):\(tcp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "?.?.?.?.") - SYN:\(tcp.syn), SEQ#:\(SequenceNumber(tcp.sequenceNumber)), ACK#:\(SequenceNumber(tcp.acknowledgementNumber)), CHK:\(tcp.checksum).data.hex")

            // SYN gives us a sequence number, so reset the straw sequence number
            let oldStrawSequenceNumber = await downstreamStraw.sequenceNumber()
            self.downstreamStraw = TCPDownstreamStraw(segmentStart: oldStrawSequenceNumber, windowSize: tcp.windowSize)
            self.upstreamStraw = TCPUpstreamStraw(segmentStart: SequenceNumber(tcp.sequenceNumber))

            self.logger.debug("TcpSynReceived: staying in SYN-RECEIVED, using new SYN, sending new SYN-ACK")
            if identity.remotePort == 7 || identity.remotePort == 853
            {
                self.tcpLogger.debug("TcpSynReceived: staying in SYN-RECEIVED, using new SYN, sending new SYN-ACK")
                self.tcpLogger.trace("IPv4 of new SYN: \(ipv4.description)")
                self.tcpLogger.trace("TCP of new SYN: \(tcp.description)")
            }

            // Send a SYN-ACK for the new SYN
            let sequenceNumber = await downstreamStraw.sequenceNumber()
            let acknowledgementNumber = await upstreamStraw.acknowledgementNumber()
            let windowSize = await downstreamStraw.windowSize()
            let synAck = try await self.makeSynAck(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize)

            let packet = Packet(ipv4Bytes: synAck.data, timestamp: Date())
            if let ipv4 = packet.ipv4, let tcp = packet.tcp
            {
                self.logger.trace("<- TcpSynReceived.SYN-ACK: \(ipv4.sourceAddress.ipv4AddressString ?? "?.?.?.?."):\(tcp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "?.?.?.?.") - SYN:\(tcp.syn), SEQ#:\(SequenceNumber(tcp.sequenceNumber)), ACK#:\(SequenceNumber(tcp.acknowledgementNumber)), CHK:\(tcp.checksum).data.hex")
                self.tcpLogger.trace("IPv4 of new SYN-ACK: \(ipv4.description)")
                self.tcpLogger.trace("TCP of new SYN-ACK: \(tcp.description)")
            }

            return TcpStateTransition(newState: self, packetsToSend: [synAck])
        }

        // We expect to receive an ACK.
        guard tcp.ack else
        {
            self.logger.trace("-> TcpSynReceived.ACK: \(ipv4.sourceAddress.ipv4AddressString ?? "?.?.?.?."):\(tcp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "?.?.?.?.") - ACK:\(tcp.ack), SEQ#:\(SequenceNumber(tcp.sequenceNumber)), ACK#:\(SequenceNumber(tcp.acknowledgementNumber)), CHK:\(tcp.checksum).data.hex")

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

            let sequenceNumber = await downstreamStraw.sequenceNumber()
            let acknowledgementNumber = await upstreamStraw.acknowledgementNumber()
            let windowSize = await downstreamStraw.windowSize()
            let synAck = try await self.makeSynAck(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize)
            return TcpStateTransition(newState: self, packetsToSend: [synAck])
        }

        self.tcpLogger.trace("IPv4 of ACK: \(ipv4.description)")
        self.tcpLogger.trace("TCP of ACK: \(tcp.description)")

        // We have an ACK for our SYN-ACK. Change to ESTABLISHED state.
        return TcpStateTransition(newState: TcpEstablished(self))
    }

    func makeSynAck(sequenceNumber: SequenceNumber, acknowledgementNumber: SequenceNumber, windowSize: UInt16) async throws -> IPv4
    {
        return try await self.makePacket(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize, syn: true, ack: true)
    }
}

public enum TcpSynReceivedError: Error
{
}
