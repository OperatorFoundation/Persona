//
//  TcpEstablished.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/5/23.
//

import Foundation

import InternetProtocols

public class TcpEstablished: TcpStateHandler
{
    override public func processDownstreamPacket(stats: Stats, ipv4: IPv4, tcp: TCP, payload: Data?) async throws -> TcpStateTransition
    {
        stats.established += 1
        if tcp.syn { stats.syn += 1}
        if tcp.fin { stats.syn += 1}
        if tcp.rst { stats.rst += 1}
        if !tcp.syn, !tcp.fin, !tcp.rst, !tcp.ack { stats.noFlags += 1 }
        if tcp.ack
        {
            stats.ack += 1

            if self.straw.inWindow(tcp) { stats.inWindow += 1 } else { stats.outOfWindow += 1 }
            if tcp.payload == nil { stats.noPayload += 1 } else { stats.payload += 1 }
        }

        let clientWindow = self.straw.clientWindow(size: tcp.windowSize)
        let packetLowerBound = SequenceNumber(tcp.sequenceNumber)

        var packetUpperBound: SequenceNumber = packetLowerBound
        if let payload
        {
            packetUpperBound = packetUpperBound.add(payload.count)
        }

        if tcp.syn
        {
            packetUpperBound = packetUpperBound.increment()

            let (sequenceNumber, acknowledgementNumber, windowSize) = self.getState()

            stats.sentipv4 += 1
            stats.senttcp += 1
            stats.sentestablished += 1
            stats.sentrst += 1
            let rst = try self.makeRst(ipv4: ipv4, tcp: tcp, sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize)

            let closed = TcpClosed(self)
            return TcpStateTransition(newState: closed, packetsToSend: [rst])
        }
        
        if tcp.rst
        {
            return try await handleRstSynchronizedState(stats: stats, ipv4: ipv4, tcp: tcp)
        }

        guard self.straw.inWindow(tcp) else
        {
            self.logger.debug("TcpEstablished - Out of window: \nClient Window: lower bound - \(clientWindow.lowerBound), upper bound - \(clientWindow.upperBound) \nPacket: lower bound - \(packetLowerBound) upper bound - \(packetUpperBound)")

            // Send an ACK to let the client know that they are outside of the TCP window.
            stats.sentipv4 += 1
            stats.senttcp += 1
            stats.sentestablished += 1
            stats.sentack += 1
            stats.sentnopayload += 1
            stats.windowCorrection += 1
            let ack = try await self.makeAck(stats: stats)
            return TcpStateTransition(newState: self, packetsToSend: [ack])
        }
        
        #if DEBUG
        self.logger.debug("✅ TcpEstablished - \(clientWindow.lowerBound) <= \(packetLowerBound)..<\(packetUpperBound) <= \(clientWindow.upperBound)")
        #endif
        
        self.windowSize = tcp.windowSize

        if tcp.ack
        {
            #if DEBUG
            self.logger.debug("👋 New ACK# Received - \(tcp.acknowledgementNumber)")
            #endif
            
            let acknowledgementNumber = SequenceNumber(tcp.acknowledgementNumber)

            #if DEBUG
            self.logger.debug("Retransmission queue has \(self.retransmissionQueue.count) segments before ACK")
            #endif

            self.retransmissionQueue.acknowledge(acknowledgementNumber: acknowledgementNumber)

            #if DEBUG
            self.logger.debug("Retransmission queue has \(self.retransmissionQueue.count) segments after ACK")
            #endif
        }
        
        var packets: [IPv4] = []
        
        if let payload = tcp.payload
        {
            try await self.write(payload: payload)
            self.straw.increaseAcknowledgementNumber(payload.count)

            // We have new data. We need to send an ACK.
            // Is there room in the receive window to send a payload with the ACK?
            // And do we have a payload to include in the ACK?
            if self.retransmissionQueue.bytes < self.windowSize, self.straw.count > 0
            {
                packets = try await self.pumpStrawToClient(stats, tcp)
            }
            else // No room in the receive window or no data to send, send a bare ACK instead.
            {
                packets = [try await self.makeAck(stats: stats)]
            }
        }

        if tcp.fin
        {
            self.straw.increaseAcknowledgementNumber(1)
            let finack = try await makeFinAck()
            packets.append(finack) // ACK and FIN

            try await self.close()

            return TcpStateTransition(newState: TcpCloseWait(self), packetsToSend: packets)
        }
        else
        {
            return TcpStateTransition(newState: self, packetsToSend: packets)
        }
    }

    override public func processUpstreamData(stats: Stats, data: Data) async throws -> TcpStateTransition
    {
        guard data.count > 0 else
        {
            return TcpStateTransition(newState: self)
        }

        try self.straw.write(data)

        let packets = try await self.pumpStrawToClient(stats)
        return TcpStateTransition(newState: self, packetsToSend: packets)
    }

    override public func processUpstreamClose(stats: Stats) async throws -> TcpStateTransition
    {
        return TcpStateTransition(newState: TcpFinWait1(self))
    }
}

public enum TcpEstablishedError: Error
{
    case missingStraws
}
