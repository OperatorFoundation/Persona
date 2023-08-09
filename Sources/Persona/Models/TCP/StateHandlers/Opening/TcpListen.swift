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
        guard !tcp.rst else
        {
            throw TcpListenError.rstReceived
        }

        guard !tcp.fin else
        {
            // Send a RST and close.
            return try self.panicOnDownstream(ipv4: ipv4, tcp: tcp, payload: payload)
        }

        guard !tcp.ack else
        {
            return try self.panicOnDownstream(ipv4: ipv4, tcp: tcp, payload: payload)
        }

        // In the LISTEN state, we only accept a SYN.
        guard tcp.syn else
        {
            // Send a RST and close.
            return try self.panicOnDownstream(ipv4: ipv4, tcp: tcp, payload: payload)
        }

        self.upstreamStraw = TCPUpstreamStraw(segmentStart: SequenceNumber(tcp.sequenceNumber))

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
