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
    override public func processDownstreamPacket(ipv4: IPv4, tcp: TCP, payload: Data?) throws -> TcpStateTransition
    {
        self.logger.debug("TcpListen.processDownstreamPacket: \(identity.localAddress):\(identity.localPort) -> \(identity.remoteAddress):\(identity.remotePort)")
        if identity.remotePort == 7
        {
            self.tcpLogger.debug("TcpListen.procesDownstreamPacket: \(identity.localAddress):\(identity.localPort) -> \(identity.remoteAddress):\(identity.remotePort)")
        }

        guard !tcp.rst else
        {
            self.logger.debug("TcpListen.processDownstreamPacket: packet rejected because of RST")
            if identity.remotePort == 7
            {
                self.tcpLogger.debug("TcpListen.processDownstreamPacket: packet rejected because of RST")
            }

            throw TcpListenError.rstReceived
        }

        guard !tcp.fin else
        {
            self.logger.debug("TcpListen.processDownstreamPacket: packet rejected because of FIN")
            if identity.remotePort == 7
            {
                self.tcpLogger.debug("TcpListen.processDownstreamPacket: packet rejected because of FIN")
            }

            // Send a RST and close.
            return try self.panicOnDownstream(ipv4: ipv4, tcp: tcp, payload: payload)
        }

        guard !tcp.ack else
        {
            self.logger.debug("TcpListen.processDownstreamPacket: packet rejected because of ACK")
            if identity.remotePort == 7
            {
                self.tcpLogger.debug("TcpListen.processDownstreamPacket: packet rejected because of ACK")
            }

            return try self.panicOnDownstream(ipv4: ipv4, tcp: tcp, payload: payload)
        }

        // In the LISTEN state, we only accept a SYN.
        guard tcp.syn else
        {
            self.logger.debug("TcpListen.processDownstreamPacket: packet rejected because of lack of SYN")
            if identity.remotePort == 7
            {
                self.tcpLogger.debug("TcpListen.processDownstreamPacket: packet rejected because of lack of SYN")
            }

            // Send a RST and close.
            return try self.panicOnDownstream(ipv4: ipv4, tcp: tcp, payload: payload)
        }

        self.upstreamStraw = TCPUpstreamStraw(segmentStart: SequenceNumber(tcp.sequenceNumber))

        self.logger.debug("TcpListen.processDownstreamPacket: Packeted accepted! Sending SYN-ACK and switching to SYN-RECEIVED state")
        if identity.remotePort == 7
        {
            self.tcpLogger.debug("TcpListen.processDownstreamPacket: Packeted accepted! Sending SYN-ACK and switching to SYN-RECEIVED state")
        }

        let synAck = try self.makeSynAck()
        let synReceived = TcpSynReceived(self)
        return TcpStateTransition(newState: synReceived, packetsToSend: [synAck])
    }

    func makeSynAck() throws -> IPv4
    {
        return try self.makePacket(sequenceNumber: self.downstreamStraw.sequenceNumber, acknowledgementNumber: self.upstreamStraw.acknowledgementNumber, syn: true, ack: true)
    }
}

public enum TcpListenError: Error
{
    case listenStateRequiresSynPacket
    case rstReceived
}
