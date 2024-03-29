//
//  TcpStateHandler.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/5/23.
//

import Foundation
import Logging

import InternetProtocols
import Puppy
import TransmissionAsync

public enum TcpProxyMessage: UInt8
{
    case upstreamOnly   = 1
    case downstreamOnly = 2
    case bidirectional  = 3
    case close          = 4

    public init?(data: Data)
    {
        guard data.count == 1 else
        {
            return nil
        }

        self.init(rawValue: data[0])
    }

    public var data: Data
    {
        return Data(array: [self.rawValue])
    }
}

public class TcpStateHandler
{
    public let identity: Identity
    public let downstream: AsyncConnection
    public let logger: Logger
    public let tcpLogger: Puppy
    public let writeLogger: Puppy

    public var straw: TCPStraw
    public var open: Bool = true
    var retransmissionQueue: RetransmissionQueue = RetransmissionQueue()

    public init(identity: Identity, downstream: AsyncConnection, logger: Logger, tcpLogger: Puppy, writeLogger: Puppy)
    {
        self.identity = identity
        self.downstream = downstream
        self.logger = logger
        self.tcpLogger = tcpLogger
        self.writeLogger = writeLogger

        self.straw = TCPStraw(logger: self.logger, sequenceNumber: isn(), acknowledgementNumber: SequenceNumber(0))
    }

    public init(_ oldState: TcpStateHandler)
    {
        self.identity = oldState.identity
        self.downstream = oldState.downstream
        self.logger = oldState.logger
        self.tcpLogger = oldState.tcpLogger
        self.writeLogger = oldState.writeLogger

        self.straw = oldState.straw
    }

    public func processDownstreamPacket(stats: Stats, ipv4: IPv4, tcp: TCP, payload: Data?) async throws -> TcpStateTransition
    {
        self.logger.debug("TcpStateHandler.processDownstreamPacket: \(ipv4.sourceAddress.ipv4AddressString ?? "?.?.?.?"):\(tcp.sourcePort) -> \(ipv4.destinationAddress.data.ipv4AddressString ?? "?.?.?.?"):\(tcp.destinationPort)")
        if tcp.destinationPort == 7
        {
            self.tcpLogger.debug("TcpStateHandler.processDownstreamPacket: \(ipv4.sourceAddress.ipv4AddressString ?? "?.?.?.?"):\(tcp.sourcePort) -> \(ipv4.destinationAddress.data.ipv4AddressString ?? "?.?.?.?"):\(tcp.destinationPort)")
        }

        return try await self.panicOnDownstream(ipv4: ipv4, tcp: tcp, payload: payload, sequenceNumber: SequenceNumber(0), acknowledgementNumber: SequenceNumber(tcp.sequenceNumber), windowSize: 0)
    }

    public func processUpstreamConnectSuccess() async throws -> TcpStateTransition
    {
        return TcpStateTransition(newState: self)
    }

    public func processUpstreamConnectFailure() async throws -> TcpStateTransition
    {
        return TcpStateTransition(newState: self)
    }

    public func processUpstreamData(stats: Stats, data: Data) async throws -> TcpStateTransition
    {
        return self.panicOnUpstream(data: data)
    }

    public func processUpstreamClose(stats: Stats) async throws -> TcpStateTransition
    {
        return self.panicOnUpstreamClose()
    }

    public func write(payload: Data) async throws
    {
        let message = TcpProxyRequest(type: .RequestWrite, identity: self.identity, payload: payload)

        #if DEBUG
        self.logger.debug("<< ESTABLISHED \(message)")
        #endif

        try await self.downstream.writeWithLengthPrefix(message.data, 32)
    }

    func close() async throws
    {
        let message = TcpProxyRequest(type: .RequestClose, identity: self.identity)

        #if DEBUG
        self.logger.debug("<< ESTABLISHED \(message)")
        #endif

        try await self.downstream.writeWithLengthPrefix(message.data, 32)
    }

    func getState() -> (sequenceNumber: SequenceNumber, acknowledgeNumber: SequenceNumber, windowSize: UInt16)
    {
        // Our sequence number is taken from upstream.
        let sequenceNumber = self.straw.sequenceNumber

        // We acknowledge bytes we have handled from downstream.
        let acknowledgementNumber = self.straw.acknowledgementNumber

        // Our window size is how many more bytes we are willing to accept from downstream.
        let windowSize = TCPStraw.serverWindowSize

        return (sequenceNumber, acknowledgementNumber, windowSize)
    }

    func pump() async throws -> TcpStateTransition
    {
        return TcpStateTransition(newState: self)
    }

    func pumpStrawToClient(_ stats: Stats, _ tcp: TCP? = nil) async throws -> [IPv4]
    {
        if self.retransmissionQueue.isEmpty
        {
            // Only send fresh packets when there is nothing to retransmit

            guard !self.straw.isEmpty else
            {
                return []
            }

            // We're going to split the whole buffer into individual packets.
            var packets: [IPv4] = []

            // The maximum we can send is limited by both the client window size and how much data is in the buffer.
            let sizeToSend: Int
            if let tcp
            {
                sizeToSend = min(Int(tcp.windowSize), self.straw.count)

                if tcp.ack
                {
                    if let segment = try? self.retransmissionQueue.next()
                    {
                        let result = try await self.makeAck(stats: stats, segment: segment)
                        return [result]
                    }
                }
            }
            else
            {
                sizeToSend = self.straw.count
            }

            var totalPayloadSize = 0
            var nextSequenceNumber = self.straw.sequenceNumber

            // We're trying to hit this limit exactly, but if we send to many packets at once they'll get discarded.
            // So try our best, but limit it to 3 packets max.
            while totalPayloadSize < sizeToSend, packets.count < TcpProxy.optimism
            {
                // Each packet is limited is by the amount left to send and the MTU (which we guess).
                let nextPacketSize = min(sizeToSend - totalPayloadSize, 1400)

                let window = SequenceNumberRange(lowerBound: nextSequenceNumber, size: UInt32(nextPacketSize))

                let packet = try await self.makeAck(stats: stats, window: window)
                if let payload = packet.payload
                {
                    packets.append(packet)

                    let segment = Segment(data: payload, sequenceNumber: window.lowerBound)
                    self.retransmissionQueue.add(segment: segment)
                }

                stats.sentipv4 += 1
                stats.senttcp += 1
                stats.sentestablished += 1
                stats.sentack += 1
                stats.sentpayload += 1
                stats.fresh += 1

                totalPayloadSize = totalPayloadSize + nextPacketSize
                nextSequenceNumber = nextSequenceNumber.add(nextPacketSize)
            }

            return packets
        }
        else
        {
            // Retransmitting

            guard let segment = try? self.retransmissionQueue.next() else
            {
                // We might fail to retrieve anything because it is too soon to retransmit.
                // In this case, do nothing and wait until it is time to retransmit.
                
                return []
            }

            guard let packet = try? await self.makeAck(stats: stats, segment: segment) else
            {
                return []
            }

            stats.retransmission += 1

            return [packet]
        }
    }

    /// In all states except SYN-SENT, all reset (RST) segments are validated by checking their SEQ-fields.
    /// A reset is valid if its sequence number is in the window.
    ///
    /// The receiver of a RST first validates it, then changes state.
    func handleRstSynchronizedState(stats: Stats, ipv4: IPv4, tcp: TCP) async throws -> TcpStateTransition
    {
        let packetLowerBound = SequenceNumber(tcp.sequenceNumber)
        var packetUpperBound = packetLowerBound
        
        guard self.straw.inWindow(tcp) else
        {
            self.logger.error("❌ handleRstSynchronizedState - sequenceNumber (\(packetLowerBound)) not in window")

            let ack = try await self.makeAck(stats: stats)
            return TcpStateTransition(newState: self, packetsToSend: [ack])
        }
        
        packetUpperBound = packetUpperBound.increment()

        let (sequenceNumber, acknowledgementNumber, windowSize) = self.getState()
        let rst = try self.makeRst(ipv4: ipv4, tcp: tcp, sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize)
        let closed = TcpClosed(self)
        
        return TcpStateTransition(newState: closed, packetsToSend: [rst])
    }

    func makeRst(ipv4: IPv4, tcp: TCP, sequenceNumber: SequenceNumber, acknowledgementNumber: SequenceNumber, windowSize: UInt16) throws -> IPv4
    {
        return try self.makePacket(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize, rst: true)
    }

    func makeAck(stats: Stats, segment: Segment) async throws -> IPv4
    {
        let (_, acknowledgementNumber, windowSize) = self.getState()

        stats.retransmission += 1

        return try self.makePacket(sequenceNumber: segment.window.lowerBound, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize, ack: true, payload: segment.data)
    }

    func makeAck(stats: Stats, maxSize: Int) async throws -> IPv4
    {
        stats.fresh += 1

        let (_, acknowledgementNumber, windowSize) = self.getState()

        let segment = try self.straw.read(maxSize: maxSize)

        return try self.makePacket(sequenceNumber: segment.window.lowerBound, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize, ack: true, payload: segment.data)
    }

    func makeAck(stats: Stats, window: SequenceNumberRange? = nil) async throws -> IPv4
    {
        if let window
        {
            let (_, acknowledgementNumber, windowSize) = self.getState()

            if window.lowerBound.uint32 < self.straw.highWaterMark.uint32 // Ignore wrapover for simple statistics gathering purposes
            {
                stats.retransmission += 1
            }
            else
            {
                stats.fresh += 1
            }

            let segment = try self.straw.read(window: window)

            return try self.makePacket(sequenceNumber: segment.window.lowerBound, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize, ack: true, payload: segment.data)
        }
        else
        {
            let (sequenceNumber, acknowledgementNumber, windowSize) = self.getState()
            return try self.makePacket(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize, ack: true, payload: nil)
        }
    }
    
    func makeFinAck(window: SequenceNumberRange? = nil) async throws -> IPv4
    {
        if let window
        {
            let (_, acknowledgementNumber, windowSize) = self.getState()

            let segment = try self.straw.read(window: window)
            return try self.makePacket(sequenceNumber: segment.window.lowerBound, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize, ack: true, fin: true)
        }
        else
        {
            let (sequenceNumber, acknowledgementNumber, windowSize) = self.getState()
            return try self.makePacket(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize, ack: true, fin: true)
        }
    }

    func makePacket(sequenceNumber: SequenceNumber, acknowledgementNumber: SequenceNumber, windowSize: UInt16, syn: Bool = false, ack: Bool = false, fin: Bool = false, rst: Bool = false, payload: Data? = nil) throws -> IPv4
    {
        do
        {
            guard let ipv4 = try IPv4(sourceAddress: self.identity.remoteAddress, destinationAddress: self.identity.localAddress, sourcePort: self.identity.remotePort, destinationPort: self.identity.localPort, sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, syn: syn, ack: ack, fin: fin, rst: rst, windowSize: windowSize, payload: payload) else
            {
                self.logger.debug("* sendPacket() failed to initialize IPv4 packet.")
                self.tcpLogger.debug("* sendPacket() failed to initialize IPv4 packet.")
                throw TcpProxyError.badIpv4Packet
            }

            return ipv4
        }
        catch
        {
            self.logger.debug("* sendPacket() failed to initialize IPv4 packet. Received an error: \(error)")
            self.tcpLogger.debug("* sendPacket() failed to initialize IPv4 packet. Received an error: \(error)")
            throw error
        }
    }

    // Send a RST and close.
    func panicOnDownstream(ipv4: IPv4, tcp: TCP, payload: Data?, sequenceNumber: SequenceNumber, acknowledgementNumber: SequenceNumber, windowSize: UInt16) async throws -> TcpStateTransition
    {
        self.logger.debug("TcpStateHandler.panicOnDownstream: \(ipv4.sourceAddress.ipv4AddressString ?? "not an IPv4 address"):\(tcp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "not an IPv4 address"):\(tcp.destinationPort), closing, sending RST")
        if tcp.destinationPort == 7 || tcp.destinationPort == 853
        {
            self.tcpLogger.debug("TcpStateHandler.panicOnDownstream: \(ipv4.sourceAddress.ipv4AddressString ?? "not an IPv4 address"):\(tcp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "not an IPv4 address"):\(tcp.destinationPort), closing, sending RST")
        }

        let rst = try self.makeRst(ipv4: ipv4, tcp: tcp, sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize)
        return TcpStateTransition(newState: TcpClosed(self), packetsToSend: [rst])
    }

    func panicOnDownstreamClose() -> TcpStateTransition
    {
        self.logger.debug("TcpStateHandler.panicOnDownstreamClose, closing")

        return TcpStateTransition(newState: TcpClosed(self))
    }

    func panicOnUpstream(data: Data?) -> TcpStateTransition
    {
        self.logger.debug("TcpStateHandler.panicOnUpstream, closing")

        return TcpStateTransition(newState: TcpClosed(self))
    }

    func panicOnUpstreamClose() -> TcpStateTransition
    {
        self.logger.debug("TcpStateHandler.panicOnUpstreamClose, closing")

        return TcpStateTransition(newState: TcpClosed(self))
    }
}

public enum TcpStateHandlerError: Error
{
    case missingStraws
}

