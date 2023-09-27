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
        if tcp.ack { stats.ack += 1}
        if !tcp.syn, !tcp.fin, !tcp.rst, !tcp.ack { stats.noFlags += 1 }
        if tcp.payload == nil { stats.noPayload += 1 } else { stats.payload += 1 }

        self.lastUsed = Date() // now

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

            let rst = try self.makeRst(ipv4: ipv4, tcp: tcp, sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize)

            let closed = TcpClosed(self)
            return TcpStateTransition(newState: closed, packetsToSend: [rst])
        }
        
        if tcp.rst
        {
            return try await handleRstSynchronizedState(ipv4: ipv4, tcp: tcp)
        }

        guard self.straw.inWindow(tcp) else
        {
            self.logger.error("❌ TcpEstablished - \(clientWindow.lowerBound) <= \(packetLowerBound)..<\(packetUpperBound) <= \(clientWindow.upperBound)")

            // Send an ACK to let the client know that they are outside of the TCP window.
            let ack = try await self.makeAck()
            return TcpStateTransition(newState: self, packetsToSend: [ack])
        }

        #if DEBUG
        self.logger.debug("✅ TcpEstablished - \(clientWindow.lowerBound) <= \(packetLowerBound)..<\(packetUpperBound) <= \(clientWindow.upperBound)")
        #endif

        if tcp.ack
        {
            let acknowledgementNumber = SequenceNumber(tcp.acknowledgementNumber)

            if acknowledgementNumber != self.straw.sequenceNumber
            {
                let difference = acknowledgementNumber - self.straw.sequenceNumber

                #if DEBUG
                self.logger.debug("New ACK# - clearing \(difference) of \(self.straw.count) bytes")
                #endif

                try self.straw.acknowledge(acknowledgementNumber)

                #if DEBUG
                self.logger.debug("Straw now has \(self.straw.count) bytes in the buffer")
                #endif
            }
        }

        if let payload = tcp.payload
        {
            let message = TcpProxyRequest(type: .RequestWrite, identity: self.identity, payload: payload)

            #if DEBUG
            self.logger.debug("<< ESTABLISHED \(message)")
            #endif

            try await self.downstream.writeWithLengthPrefix(message.data, 32)
            self.straw.increaseAcknowledgementNumber(payload.count)
        }

        var packets = try await self.pumpStrawToClient(tcp)

        if tcp.fin
        {
            self.straw.increaseAcknowledgementNumber(1)
            let ack = try await makeAck()
            packets.append(ack) // ACK the FIN

            let message = TcpProxyRequest(type: .RequestClose, identity: self.identity)

            #if DEBUG
            self.logger.debug("<< ESTABLISHED \(message)")
            #endif

            try await self.downstream.writeWithLengthPrefix(message.data, 32)

            return TcpStateTransition(newState: TcpCloseWait(self), packetsToSend: packets)
        }
        else
        {
            if packets.isEmpty
            {
                let ack = try await makeAck()
                packets.append(ack)
            }

            return TcpStateTransition(newState: self, packetsToSend: packets)
        }
    }

    override public func processUpstreamData(data: Data) async throws -> TcpStateTransition
    {
        guard data.count > 0 else
        {
            return TcpStateTransition(newState: self)
        }

        try self.straw.write(data)

        var packets = try await self.pumpStrawToClient()

        if packets.isEmpty
        {
            let ack = try await makeAck()
            packets.append(ack)
        }

        return TcpStateTransition(newState: self, packetsToSend: packets, progress: true)
    }

    override public func processUpstreamClose() async throws -> TcpStateTransition
    {
        return TcpStateTransition(newState: TcpFinWait1(self))
    }
}

public enum TcpEstablishedError: Error
{
    case missingStraws
}
