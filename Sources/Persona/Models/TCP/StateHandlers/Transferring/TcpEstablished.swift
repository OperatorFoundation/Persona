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
        let clientWindow = self.straw.clientWindow(size: tcp.windowSize)
        let packetLowerBound = SequenceNumber(tcp.sequenceNumber)

        var packetUpperBound: SequenceNumber = packetLowerBound
        if let payload
        {
            packetUpperBound = packetUpperBound.add(payload.count)
        }

        if tcp.syn || tcp.rst
        {
            packetUpperBound = packetUpperBound.increment()

            let (sequenceNumber, acknowledgementNumber, windowSize) = self.getState()

            let rst = try self.makeRst(ipv4: ipv4, tcp: tcp, sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize)

            let closed = TcpClosed(self)
            return TcpStateTransition(newState: closed, packetsToSend: [rst])
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

        var serverIsStillOpen: Bool = true
        if tcp.payload != nil
        {
            serverIsStillOpen = try await self.pumpClientToServer(tcp)
        }

        if serverIsStillOpen
        {
            serverIsStillOpen = await self.pumpServerToStraw(tcp)
        }

        var packets = try await self.pumpStrawToClient(tcp)

        // There are three possible outcomes now:
        // - server is open, FIN      - CLOSE-WAIT
        // - server is open, no FIN   - ESTABLISHED
        // - server is closed, FIN    - CLOSING
        // - server is closed, no FIN - FIN-WAIT-1
        if serverIsStillOpen
        {
            if tcp.fin
            {
                // - server is open, FIN      - CLOSE-WAIT

                self.straw.increaseAcknowledgementNumber(1)
                let ack = try await makeAck()
                packets.append(ack) // ACK the FIN

                return TcpStateTransition(newState: TcpCloseWait(self), packetsToSend: packets)
            }
            else
            {
                // - server is open, no FIN   - ESTABLISHED
                if packets.isEmpty
                {
                    let ack = try await makeAck()
                    packets.append(ack)
                }

                return TcpStateTransition(newState: self, packetsToSend: packets)
            }
        }
        else
        {
            if tcp.fin
            {
                // - server is closed, FIN    - CLOSING

                self.straw.increaseAcknowledgementNumber(1)
                let ack = try await makeAck()
                packets.append(ack) // ACK the FIN

                return TcpStateTransition(newState:TcpClosing(self), packetsToSend: packets)
            }
            else
            {
                // - server is closed, no FIN - FIN-WAIT-1
                if packets.isEmpty
                {
                    let ack = try await makeAck()
                    packets.append(ack)
                }

                return TcpStateTransition(newState:TcpFinWait1(self), packetsToSend: packets)
            }
        }
    }
}

public enum TcpEstablishedError: Error
{
    case missingStraws
}
