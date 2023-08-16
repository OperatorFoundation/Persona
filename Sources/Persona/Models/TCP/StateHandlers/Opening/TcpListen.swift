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
        self.logger.debug("TcpListen.processDownstreamPacket: \(identity.localAddress.data.ipv4AddressString ?? "?.?.?.?"):\(identity.localPort) -> \(identity.remoteAddress.data.ipv4AddressString ?? "?.?.?.?"):\(identity.remotePort)")
        if identity.remotePort == 7 || identity.remotePort == 853
        {
            self.tcpLogger.debug("TcpListen.procesDownstreamPacket: \(identity.localAddress.data.ipv4AddressString ?? "?.?.?.?"):\(identity.localPort) -> \(identity.remoteAddress.data.ipv4AddressString ?? "?.?.?.?"):\(identity.remotePort)")
        }

        guard !tcp.rst else
        {
            self.logger.debug("TcpListen.processDownstreamPacket: packet rejected because of RST")
            if identity.remotePort == 7 || identity.remotePort == 853
            {
                self.tcpLogger.debug("TcpListen.processDownstreamPacket: packet rejected because of RST")
            }

            // No need to send a RST for a RST, just fail on this packet and move to the next one.
            throw TcpListenError.rstReceived
        }

        guard !tcp.fin else
        {
            self.logger.debug("TcpListen.processDownstreamPacket: packet rejected because of FIN")
            if identity.remotePort == 7 || identity.remotePort == 853
            {
                self.tcpLogger.debug("TcpListen.processDownstreamPacket: packet rejected because of FIN")
            }

            // Send a RST and close.
            return try self.panicOnDownstream(ipv4: ipv4, tcp: tcp, payload: payload)
        }

        guard !tcp.ack else
        {
            self.logger.debug("TcpListen.processDownstreamPacket: packet rejected because of ACK")
            if identity.remotePort == 7 || identity.remotePort == 853
            {
                self.tcpLogger.debug("TcpListen.processDownstreamPacket: packet rejected because of ACK")
                self.tcpLogger.debug("Rejected packet:\n\(tcp.description)\n")
            }

            // Send a RST and close.
            return try self.panicOnDownstream(ipv4: ipv4, tcp: tcp, payload: payload)
        }

        // In the LISTEN state, we only accept a SYN.
        guard tcp.syn else
        {
            self.logger.debug("TcpListen.processDownstreamPacket: packet rejected because of lack of SYN")
            if identity.remotePort == 7 || identity.remotePort == 853
            {
                self.tcpLogger.debug("TcpListen.processDownstreamPacket: packet rejected because of lack of SYN")
            }

            // Send a RST and close.
            return try self.panicOnDownstream(ipv4: ipv4, tcp: tcp, payload: payload)
        }

        // SYN gives us a sequence number, so reset the straw sequence number (previously 0)
        self.downstreamStraw = TCPDownstreamStraw(segmentStart: self.downstreamStraw.sequenceNumber, windowSize: tcp.windowSize)
        self.upstreamStraw = TCPUpstreamStraw(segmentStart: SequenceNumber(tcp.sequenceNumber))

        self.logger.debug("TcpListen.processDownstreamPacket: Packet accepted! Sending SYN-ACK and switching to SYN-RECEIVED state")
        if identity.remotePort == 7 || identity.remotePort == 853
        {
            self.tcpLogger.debug("TcpListen.processDownstreamPacket: Packet accepted! Sending SYN-ACK and switching to SYN-RECEIVED state")
        }
        
        self.logger.debug("TcpListen.processDownstreamPacket: try to make a SYN-ACK")
        
        do
        {
            let synAck = try self.makeSynAck()
            self.logger.debug("TcpListen.processDownstreamPacket: made a SYN-ACK")
            
            let synReceived = TcpSynReceived(self)
            return TcpStateTransition(newState: synReceived, packetsToSend: [synAck])
        }
        catch
        {
            self.logger.debug("TcpListen.processDownstreamPacket: failed to make a SYN-ACK. Error: \n\(error)")
            return TcpStateTransition(newState: self)
        }
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
