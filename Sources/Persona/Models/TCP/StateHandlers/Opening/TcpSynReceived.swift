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
        // We should not be receiving a RST.
        guard !tcp.rst else
        {
            let (sequenceNumber, acknowledgementNumber, windowSize) = self.getState()
            return try await self.panicOnDownstream(ipv4: ipv4, tcp: tcp, payload: payload, sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize)
        }

        // We should not be receiving a FIN.
        guard !tcp.fin else
        {
            let (sequenceNumber, acknowledgementNumber, windowSize) = self.getState()
            return try await self.panicOnDownstream(ipv4: ipv4, tcp: tcp, payload: payload, sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize)
       }

        // In the SYN-RECEIVED state, we may received duplicate SYNs, but new SYNs are not allowed.
        if tcp.syn
        {
            let oldSequenceNumber = self.straw.acknowledgementNumber
            let newSequenceNumber = SequenceNumber(tcp.sequenceNumber)

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
            // Roll back the sequence number so that we can retry sending a SYN-ACK
            let (sequenceNumber, acknowledgementNumber, windowSize) = self.getState()
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
