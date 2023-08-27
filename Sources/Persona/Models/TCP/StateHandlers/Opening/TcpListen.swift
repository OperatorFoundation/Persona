//
//  TcpListen.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/5/23.
//

import Foundation

import InternetProtocols

public class TcpListen: TcpStateHandler
{
    override public func processDownstreamPacket(ipv4: IPv4, tcp: TCP, payload: Data?) async throws -> TcpStateTransition
    {
//        self.logger.debug("TcpListen.processDownstreamPacket: \(identity.localAddress.data.ipv4AddressString ?? "?.?.?.?"):\(identity.localPort) -> \(identity.remoteAddress.data.ipv4AddressString ?? "?.?.?.?"):\(identity.remotePort)")
//        if identity.remotePort == 7 || identity.remotePort == 853
//        {
//            self.tcpLogger.debug("TcpListen.procesDownstreamPacket: \(identity.localAddress.data.ipv4AddressString ?? "?.?.?.?"):\(identity.localPort) -> \(identity.remoteAddress.data.ipv4AddressString ?? "?.?.?.?"):\(identity.remotePort)")
//        }

        guard !tcp.rst else
        {
            self.logger.debug("TcpListen.processDownstreamPacket: packet rejected because of RST")
//            if identity.remotePort == 7 || identity.remotePort == 853
//            {
//                self.tcpLogger.debug("TcpListen.processDownstreamPacket: packet rejected because of RST")
//            }

            // No need to send a RST for a RST, just fail on this packet and move to the next one.
            throw TcpListenError.rstReceived
        }

        guard !tcp.fin else
        {
            self.logger.debug("TcpListen.processDownstreamPacket: packet rejected because of FIN")
//            if identity.remotePort == 7 || identity.remotePort == 853
//            {
//                self.tcpLogger.debug("TcpListen.processDownstreamPacket: packet rejected because of FIN")
//            }

            // Send a RST and close.
            return try await self.panicOnDownstream(ipv4: ipv4, tcp: tcp, payload: payload, sequenceNumber: SequenceNumber(0), acknowledgementNumber: SequenceNumber(0), windowSize: 0)
        }

        guard !tcp.ack else
        {
            self.logger.debug("TcpListen.processDownstreamPacket: packet rejected because of ACK")
//            if identity.remotePort == 7 || identity.remotePort == 853
//            {
//                self.tcpLogger.debug("TcpListen.processDownstreamPacket: packet rejected because of ACK")
//                self.tcpLogger.debug("Rejected packet:\n\(tcp.description)\n")
//            }

            // Send a RST and close.
            return try await self.panicOnDownstream(ipv4: ipv4, tcp: tcp, payload: payload, sequenceNumber: SequenceNumber(0), acknowledgementNumber: SequenceNumber(0), windowSize: 0)
        }

        // In the LISTEN state, we only accept a SYN.
        guard tcp.syn else
        {
            self.logger.debug("TcpListen.processDownstreamPacket: packet rejected because of lack of SYN")
//            if identity.remotePort == 7 || identity.remotePort == 853
//            {
//                self.tcpLogger.debug("TcpListen.processDownstreamPacket: packet rejected because of lack of SYN")
//            }

            // Send a RST and close.
            return try await self.panicOnDownstream(ipv4: ipv4, tcp: tcp, payload: payload, sequenceNumber: SequenceNumber(0), acknowledgementNumber: SequenceNumber(0), windowSize: 0)
        }

        // SYN gives us a sequence number, so set the sequence numbers.
        // downstreamStraw tracks the client to server data flow, upstreamStraw tracks the server to client data flow
        let irs = SequenceNumber(tcp.sequenceNumber)
        let downstreamStraw = TCPDownstreamStraw(segmentStart: irs, acknowledgementNumber: SequenceNumber(tcp.acknowledgementNumber), windowSize: tcp.windowSize)
        let upstreamStraw = TCPUpstreamStraw(segmentStart: isn(), acknowledgementNumber: irs.increment())
        self.downstreamStraw = downstreamStraw
        self.upstreamStraw = upstreamStraw

        self.logger.debug("TcpListen.processDownstreamPacket: Packet accepted! Sending SYN-ACK and switching to SYN-RECEIVED state")
//        self.logger.trace("-> TcpListen.SYN: \(ipv4.sourceAddress.ipv4AddressString ?? "?.?.?.?."):\(tcp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "?.?.?.?.") - SYN:\(tcp.syn), SEQ#:\(SequenceNumber(tcp.sequenceNumber)), ACK#:\(SequenceNumber(tcp.acknowledgementNumber)), CHK:\(tcp.checksum).data.hex")
//        if identity.remotePort == 7 || identity.remotePort == 853
//        {
//            self.tcpLogger.debug("TcpListen.processDownstreamPacket: Packet accepted! Sending SYN-ACK and switching to SYN-RECEIVED state")
//            self.logger.trace("-> TcpListen.SYN: \(description(ipv4, tcp))")
//            self.tcpLogger.trace("-> TcpListen.SYN: \(description(ipv4, tcp))")
//        }
        
//        self.logger.debug("TcpListen.processDownstreamPacket: try to make a SYN-ACK")
        
        do
        {
            let sequenceNumber = await upstreamStraw.sequenceNumber()
            let acknowledgementNumber = await upstreamStraw.acknowledgementNumber()
            let windowSize = await upstreamStraw.windowSize()

            let synAck = try self.makeSynAck(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize)
//            self.logger.debug("TcpListen.processDownstreamPacket: made a SYN-ACK")

//            let packet = Packet(ipv4Bytes: synAck.data, timestamp: Date())
//            if let ipv4 = packet.ipv4, let tcp = packet.tcp
//            {
//                self.logger.trace("IPv4 of SYN-ACK: \(ipv4.description)")
//                self.logger.trace("TCP of SYN-ACK: \(tcp.description)")
//                self.logger.trace("<- TcpListen.SYN-ACK: \(description(ipv4, tcp))")
//                self.tcpLogger.trace("<- TcpListen.SYN-ACK: \(description(ipv4, tcp))")
//            }

            let synReceived = TcpSynReceived(self)
            return TcpStateTransition(newState: synReceived, packetsToSend: [synAck])
        }
        catch
        {
            self.logger.debug("TcpListen.processDownstreamPacket: failed to make a SYN-ACK. Error: \n\(error)")
            return TcpStateTransition(newState: self)
        }
    }

    func makeSynAck(sequenceNumber: SequenceNumber, acknowledgementNumber: SequenceNumber, windowSize: UInt16) throws -> IPv4
    {
//        self.logger.trace("TcpListen.makeSynAck")
        return try self.makePacket(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize, syn: true, ack: true)
    }
}

public enum TcpListenError: Error
{
    case listenStateRequiresSynPacket
    case rstReceived
}
