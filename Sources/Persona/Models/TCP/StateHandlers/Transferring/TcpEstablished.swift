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
    override public func processDownstreamPacket(ipv4: IPv4, tcp: TCP, payload: Data?) async throws -> TcpStateTransition
    {
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

        self.logger.error("✅ TcpEstablished - \(clientWindow.lowerBound) <= \(packetLowerBound)..<\(packetUpperBound) <= \(clientWindow.upperBound)")

        if tcp.ack
        {
            let acknowledgementNumber = SequenceNumber(tcp.acknowledgementNumber)

            if acknowledgementNumber != self.straw.sequenceNumber
            {
                let difference = acknowledgementNumber - self.straw.sequenceNumber
                self.logger.debug("New ACK# - clearing \(difference) of \(self.straw.count) bytes")
                try self.straw.acknowledge(acknowledgementNumber)
                self.logger.debug("Straw now has \(self.straw.count) bytes in the buffer")
            }
        }

        if let payload = tcp.payload
        {
            let message = TcpProxyRequest(type: .RequestWrite, identity: self.identity, payload: payload)
            self.logger.info("<< ESTABLISHED \(message)")
            try await self.downstream.writeWithLengthPrefix(message.data, 32)
            self.straw.increaseAcknowledgementNumber(payload.count)
        }

        var packets = try await self.pumpStrawToClient(tcp)

        self.logger.debug("checking for closing conditions")
        // There are three possible outcomes now:
        if tcp.fin
        {
            self.logger.debug("TcpEstablished - open, FIN")
            // - server is open, FIN      - CLOSE-WAIT

            self.straw.increaseAcknowledgementNumber(1)
            let ack = try await makeAck()
            packets.append(ack) // ACK the FIN

            return TcpStateTransition(newState: TcpCloseWait(self), packetsToSend: packets)
        }
        else
        {
            self.logger.debug("TcpEstablished - open, no FIN")
            // - server is open, no FIN   - ESTABLISHED
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
        let now = Date().timeIntervalSince1970
        let then = self.lastUsed.timeIntervalSince1970
        let interval = now - then
        if interval < 0.1 // 100 ms
        {
            return TcpStateTransition(newState: self, packetsToSend: [])
        }

        if self.straw.isEmpty
        {
            if data.count > 0
            {
                try self.straw.write(data)
                self.logger.debug("TcpEstablished.processUpstreamData: Persona <-- tcpproxy - \(data.count) bytes")
            }
            else
            {
                self.logger.debug("TcpEstablished.processUpstreamData: Persona <-- tcpproxy - no data")
            }
        }

        var packets = try await self.pumpStrawToClient()

        if packets.count > 0
        {
            self.lastUsed = Date() // now
        }

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
