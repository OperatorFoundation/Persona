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
    internal var windowSize: UInt16 = UInt16.max
    var retransmissionQueue: RetransmissionQueue
    

    public init(identity: Identity, downstream: AsyncConnection, logger: Logger, tcpLogger: Puppy, writeLogger: Puppy)
    {
        self.identity = identity
        self.downstream = downstream
        self.logger = logger
        self.tcpLogger = tcpLogger
        self.writeLogger = writeLogger

        self.straw = TCPStraw(logger: self.logger, sequenceNumber: isn(), acknowledgementNumber: SequenceNumber(0))
        self.retransmissionQueue = RetransmissionQueue(logger: logger)
    }

    public init(_ oldState: TcpStateHandler)
    {
        self.identity = oldState.identity
        self.downstream = oldState.downstream
        self.logger = oldState.logger
        self.tcpLogger = oldState.tcpLogger
        self.writeLogger = oldState.writeLogger

        self.straw = oldState.straw
        self.retransmissionQueue = RetransmissionQueue(logger: logger)
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
        #if DEBUG
        self.logger.debug("🪵 \(#fileID).\(#function):\(#line) - RTQ: \(self.retransmissionQueue.count), Straw: \(self.straw.count)")
        #endif
        
        guard self.straw.count > 0 else
        {
            #if DEBUG
            self.logger.debug("🪵 \(#fileID).\(#function):\(#line) we think the straw is empty! Straw: \(self.straw.count)")
            #endif
            
            return []
        }

        // We're going to split the whole buffer into individual packets.
        var packets: [IPv4] = []

        // The maximum we can send is limited by both the client window size and how much data is in the buffer.
        var totalPacketsSize = 0
        var nextSequenceNumber = self.straw.sequenceNumber
        let maxPacketsToCreate = TcpProxy.optimism - retransmissionQueue.count

        // We're trying to hit this limit exactly, but if we send too many packets at once they'll get discarded.
        while totalPacketsSize < self.windowSize, packets.count < maxPacketsToCreate, self.straw.count > 0
        {
            #if DEBUG
            self.logger.debug("🪵 \(#fileID).\(#function):\(#line) is totalPacketsSize \(totalPacketsSize) < windowSize \(self.windowSize)?, is packets.count \(packets.count) < maxPacketsToCreate \(maxPacketsToCreate)?, is self.straw.count \(self.straw.count) > 0?")
            #endif
            // Each packet is limited is by the amount left to send and the MTU (which we guess).
            let nextPacketSize = min((Int(self.windowSize) - totalPacketsSize), TcpProxy.mtu)
            
            self.logger.debug("🪵 \(#fileID).\(#function):\(#line) about to read maxSize: \(nextPacketSize)")
            let segmentData = try self.straw.read(maxSize: nextPacketSize)
            self.logger.debug("🪵 \(#fileID).\(#function):\(#line) finished reading maxSize: \(nextPacketSize). Read \(segmentData.data.count) bytes")
            
            let segment = Segment(data: segmentData.data, sequenceNumber: nextSequenceNumber)
            let packet = try await self.makeAck(stats: stats, segment: segment)
            
            packets.append(packet)
            self.retransmissionQueue.add(segment: segment)

            stats.sentipv4 += 1
            stats.senttcp += 1
            stats.sentestablished += 1
            stats.sentack += 1
            stats.sentpayload += 1
            stats.fresh += 1

            totalPacketsSize = totalPacketsSize + nextPacketSize
            nextSequenceNumber = nextSequenceNumber.add(nextPacketSize)
            
            #if DEBUG
            self.logger.debug("🪵🪵 \(#fileID).\(#function):\(#line) is totalPacketsSize \(totalPacketsSize) < windowSize \(self.windowSize)?, is packets.count \(packets.count) < maxPacketsToCreate \(maxPacketsToCreate)?, is self.straw.count \(self.straw.count) > 0?")
            #endif
        }
        
        #if DEBUG
        self.logger.debug("🪵 \(#fileID).\(#function):\(#line) returning \(packets.count) packets.")
        #endif
        
        return packets
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
    
    /// Make an ACK with no payload
    func makeAck(stats: Stats) async throws -> IPv4
    {
        #if DEBUG
        self.logger.debug("👋 MAKE empty ACK called!!")
        #endif
        
        let (sequenceNumber, acknowledgementNumber, windowSize) = self.getState()
        return try self.makePacket(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize, ack: true, payload: nil)
    }
    
    func makeFinAck() async throws -> IPv4
    {
        let (sequenceNumber, acknowledgementNumber, windowSize) = self.getState()
        return try self.makePacket(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize, ack: true, fin: true)
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

