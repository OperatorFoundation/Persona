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
        guard !tcp.rst else
        {
            // No need to send a RST for a RST, just fail on this packet and move to the next one.
            throw TcpListenError.rstReceived
        }

        guard !tcp.fin else
        {
            /// Do not process the FIN if the state is CLOSED, LISTEN or SYN-SENT
            /// since the SEG.SEQ cannot be validated; drop the segment and return.
            return TcpStateTransition(newState: self)
        }

        guard !tcp.ack else
        {
            // Send a RST and close.
            return try await self.panicOnDownstream(ipv4: ipv4, tcp: tcp, payload: payload, sequenceNumber: SequenceNumber(0), acknowledgementNumber: SequenceNumber(0), windowSize: 0)
        }

        // In the LISTEN state, we only accept a SYN.
        guard tcp.syn else
        {
            // Send a RST and close.
            return try await self.panicOnDownstream(ipv4: ipv4, tcp: tcp, payload: payload, sequenceNumber: SequenceNumber(0), acknowledgementNumber: SequenceNumber(0), windowSize: 0)
        }

        // SYN gives us a sequence number, so set the sequence numbers.
        // downstreamStraw tracks the client to server data flow, upstreamStraw tracks the server to client data flow
        let irs = SequenceNumber(tcp.sequenceNumber) // Initial received sequence number
        let downstreamSequenceNumber = irs.increment() // Include the SYN in the count

        // Generate a random upstream sequence number
        let upstreamSequenceNumber = isn()

        // Set the acknowledgement number to the sequence number instead of 0. This signifies that nothing has been acknowledged yet and the math works out better than special casing zero.
        // Don't forget to actually send this acknowledgementNumber downstream, or else we'll be out of sync.
        self.straw = TCPStraw(sequenceNumber: upstreamSequenceNumber, acknowledgementNumber: downstreamSequenceNumber)

        do
        {
            // Our sequence number is taken from upstream.
            let (sequenceNumber, acknowledgementNumber, windowSize) = self.getState()

            let synAck = try self.makeSynAck(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize)

            // Count the SYN we sent
            self.straw.incrementSequenceNumber()

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
        return try self.makePacket(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize, syn: true, ack: true)
    }
}

public enum TcpListenError: Error
{
    case listenStateRequiresSynPacket
    case rstReceived
    case missingStraws
}
