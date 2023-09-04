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
    override public func processDownstreamPacket(ipv4: IPv4, tcp: TCP, payload: Data?) async throws -> TcpStateTransition
    {
//        self.logger.debug("TcpSynReceived.processDownstreamPacket: \(identity.localAddress.data.ipv4AddressString ?? "?.?.?.?"):\(identity.localPort) -> \(identity.remoteAddress.data.ipv4AddressString ?? "?.?.?.?"):\(identity.remotePort)")
//        if identity.remotePort == 7 || identity.remotePort == 853
//        {
//            self.tcpLogger.debug("TcpSynReceived.procesDownstreamPacket: \(identity.localAddress.data.ipv4AddressString ?? "?.?.?.?"):\(identity.localPort) -> \(identity.remoteAddress.data.ipv4AddressString ?? "?.?.?.?"):\(identity.remotePort)")
//        }

        // We should not be receiving a RST.
        guard !tcp.rst else
        {
//            self.logger.trace("-> TcpSynReceived.RST: \(ipv4.sourceAddress.ipv4AddressString ?? "?.?.?.?."):\(tcp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "?.?.?.?.") - RST:\(tcp.rst), SEQ#:\(SequenceNumber(tcp.sequenceNumber)), ACK#:\(SequenceNumber(tcp.acknowledgementNumber)), CHK:\(tcp.checksum).data.hex")
//
//            self.logger.debug("TcpSynReceived: rejected packet because of RST")
//            if identity.remotePort == 7 || identity.remotePort == 853
//            {
//                self.tcpLogger.debug("TcpSynReceived: rejected packet because of RST")
//            }

            let (sequenceNumber, acknowledgementNumber, windowSize) = try await self.getState()
            return try await self.panicOnDownstream(ipv4: ipv4, tcp: tcp, payload: payload, sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize)
        }

        // We should not be receiving a FIN.
        guard !tcp.fin else
        {
//            self.logger.trace("-> TcpSynReceived.FIN: \(ipv4.sourceAddress.ipv4AddressString ?? "?.?.?.?."):\(tcp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "?.?.?.?.") - FIN:\(tcp.fin), SEQ#:\(SequenceNumber(tcp.sequenceNumber)), ACK#:\(SequenceNumber(tcp.acknowledgementNumber)), CHK:\(tcp.checksum).data.hex")
//
//            self.logger.debug("TcpSynReceived: rejected packet because of FIN")
//            if identity.remotePort == 7 || identity.remotePort == 853
//            {
//                self.tcpLogger.debug("TcpSynReceived: rejected packet because of FIN")
//            }

            let (sequenceNumber, acknowledgementNumber, windowSize) = try await self.getState()
            return try await self.panicOnDownstream(ipv4: ipv4, tcp: tcp, payload: payload, sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize)
       }

        // In the SYN-RECEIVED state, we may received duplicate SYNs, but new SYNs are not allowed.
        if tcp.syn
        {
//            self.logger.trace("-> TcpSynReceived.SYN: \(description(ipv4, tcp))")

            let oldSequenceNumber = self.straw.acknowledgementNumber
            let newSequenceNumber = SequenceNumber(tcp.sequenceNumber)

//             self.logger.trace("old SEQ:\(oldSequenceNumber), new SEQ:\(newSequenceNumber)")

            if oldSequenceNumber == newSequenceNumber.increment()
            {
                self.logger.info("duplicate SYN \(newSequenceNumber)")

                // Send a SYN-ACK
                let (sequenceNumber, acknowledgementNumber, windowSize) = self.getState()
                let synack = try self.makeSynAck(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize)

                return TcpStateTransition(newState: self, packetsToSend: [synack])
            }
            else
            {
//                self.logger.info("brand new SYN \(newSequenceNumber) \(oldSequenceNumber)")

                // Send a RST
                let (sequenceNumber, acknowledgementNumber, windowSize) = self.getState()
                let rst = try self.makeRst(ipv4: ipv4, tcp: tcp, sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize)

                let newState = TcpListen(self)
                return TcpStateTransition(newState: newState, packetsToSend: [rst])
            }
        }

        // We expect to receive an ACK.
        guard tcp.ack else
        {
//            self.logger.trace("-> TcpSynReceived.ACK: \(description(ipv4, tcp))")
//
//            self.logger.debug("TcpSynReceived: ACK received, transitioning to ESTABLISHED, no packets to send")
//            if identity.remotePort == 7 || identity.remotePort == 853
//            {
//                self.tcpLogger.debug("TcpSynReceived: ACK received, transitioning to ESTABLISHED, no packets to send")
//            }
//
//            // They must not have heard our SYN-ACK, resend it.
//            self.logger.debug("TcpSynReceived: staying in SYN-RECEIVED, resending SYN-ACK")
//            if identity.remotePort == 7 || identity.remotePort == 853
//            {
//                self.tcpLogger.debug("TcpSynReceived: staying in SYN-RECEIVED, resending SYN-ACK")
//            }

            // Roll back the sequence number so that we can retry sending a SYN-ACK
            let (sequenceNumber, acknowledgementNumber, windowSize) = try await self.getState()
            let synAck = try self.makeSynAck(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber.decrement(), windowSize: windowSize)

            return TcpStateTransition(newState: self, packetsToSend: [synAck])
        }

        // We have an ACK for our SYN-ACK. Change to ESTABLISHED state.
        return TcpStateTransition(newState: TcpEstablished(self))
    }

    func makeSynAck(sequenceNumber: SequenceNumber, acknowledgementNumber: SequenceNumber, windowSize: UInt16) throws -> IPv4
    {
        return try self.makePacket(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize, syn: true, ack: true)
    }
}

public enum TcpSynReceivedError: Error
{
    case missingStraws
}
