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
    public let identity: TcpIdentity
    public let logger: Logger
    public let tcpLogger: Puppy
    public let writeLogger: Puppy

    public var lastUsed: Date
    public var straw: TCPStraw
    public var upstream: AsyncConnection
    public var open: Bool = true

    public init(identity: TcpIdentity, upstream: AsyncConnection, logger: Logger, tcpLogger: Puppy, writeLogger: Puppy)
    {
        self.identity = identity
        self.upstream = upstream

        self.logger = logger
        self.tcpLogger = tcpLogger
        self.writeLogger = writeLogger

        self.lastUsed = Date()

        self.straw = TCPStraw(sequenceNumber: isn(), acknowledgementNumber: SequenceNumber(0))
    }

    public init(_ oldState: TcpStateHandler)
    {
        self.identity = oldState.identity
        self.upstream = oldState.upstream
        self.logger = oldState.logger
        self.tcpLogger = oldState.tcpLogger
        self.writeLogger = oldState.writeLogger

        self.lastUsed = oldState.lastUsed

        self.straw = oldState.straw
    }

    public func processDownstreamPacket(ipv4: IPv4, tcp: TCP, payload: Data?) async throws -> TcpStateTransition
    {
        self.logger.debug("TcpStateHandler.processDownstreamPacket: \(ipv4.sourceAddress.ipv4AddressString ?? "?.?.?.?"):\(tcp.sourcePort) -> \(ipv4.destinationAddress.data.ipv4AddressString ?? "?.?.?.?"):\(tcp.destinationPort)")
        if tcp.destinationPort == 7
        {
            self.tcpLogger.debug("TcpStateHandler.processDownstreamPacket: \(ipv4.sourceAddress.ipv4AddressString ?? "?.?.?.?"):\(tcp.sourcePort) -> \(ipv4.destinationAddress.data.ipv4AddressString ?? "?.?.?.?"):\(tcp.destinationPort)")
        }

        return try await self.panicOnDownstream(ipv4: ipv4, tcp: tcp, payload: payload, sequenceNumber: SequenceNumber(0), acknowledgementNumber: SequenceNumber(tcp.sequenceNumber), windowSize: 0)
    }

    public func processUpstreamData(data: Data) throws -> TcpStateTransition
    {
        return self.panicOnUpstream(data: data)
    }

    public func processUpstreamClose() throws -> TcpStateTransition
    {
        return self.panicOnUpstreamClose()
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

    // Returns whether the server connection closed during write
    func pumpOnlyClientToServer(_ tcp: TCP) async throws -> Bool
    {
        guard let payload = tcp.payload else
        {
            return true
        }

        // Fully write all incoming payloads from the client to the server so that we don't have to buffer them.
        do
        {
            try await self.upstream.write(TcpProxyMessage.upstreamOnly.data)
            try await self.upstream.writeWithLengthPrefix(payload, 32)
            self.straw.increaseAcknowledgementNumber(payload.count)

            let data = try await self.upstream.readWithLengthPrefix(prefixSizeInBits: 32)
            if data.isEmpty
            {
                self.logger.error("Server gave us data that we did not want, discarding \(data.count) bytes")
            }

            self.logger.debug("TcpEstablished.pumpClientToServer: Persona --> tcpproxy - \(payload.count) bytes (new ACK#\(self.straw.acknowledgementNumber))")
            return true
        }
        catch
        {
            self.logger.error("Error in pumpOnlyClientToServer: \(error)")
            return false
        }
    }

    // Returns whether the server connection closed during write
    func pumpOnlyServerToStraw() async throws -> Bool
    {
        do
        {
            try await self.upstream.write(TcpProxyMessage.downstreamOnly.data)

            let data = try await self.upstream.readWithLengthPrefix(prefixSizeInBits: 32)

            if data.count > 0
            {
                try self.straw.write(data)
                self.logger.debug("TcpStateHandler.pumpOnlyServerToStraw: Persona <-- tcpproxy - \(data.count) bytes")
            }
            else
            {
                self.logger.debug("TcpStateHandler.pumpOnlyServerToStraw: Persona <-- tcpproxy - no data")
            }

            return true
        }
        catch
        {
            self.logger.error("Error in pumpOnlyServerToStraw: \(error)")
            return false
        }
    }

    // Returns whether the server connection closed during write
    func pumpBothClientToServerAndServerToStraw(_ tcp: TCP) async throws -> Bool
    {
        guard let payload = tcp.payload else
        {
            return true
        }

        // Fully write all incoming payloads from the client to the server so that we don't have to buffer them.
        do
        {
            try await self.upstream.write(TcpProxyMessage.bidirectional.data)
            try await self.upstream.writeWithLengthPrefix(payload, 32)
            self.straw.increaseAcknowledgementNumber(payload.count)
            self.logger.debug("TcpEstablished.pumpClientToServer: Persona --> tcpproxy - \(payload.count) bytes (new ACK#\(self.straw.acknowledgementNumber))")
        }
        catch
        {
            // Return early if the connection is closed, no need to try reading from a closed connection
            return false
        }

        do
        {
            // Buffer data from the server until the client ACKs it.
            let data = try await self.upstream.readWithLengthPrefix(prefixSizeInBits: 32)

            if data.count > 0
            {
                try self.straw.write(data)
                self.logger.debug("TcpEstablished.pumpBothClientToServerAndServerToStraw: Persona <-- tcpproxy - \(data.count) bytes")
            }
            else
            {
                self.logger.debug("TcpEstablished.pumpBothClientToServerAndServerToStraw: Persona <-- tcpproxy - no data")
            }

            return true
        }
        catch
        {
            self.logger.error("Error in pumpBothClientToServerAndServerToStraw: \(error)")
            return false
        }
    }

    func pumpStrawToClient(_ tcp: TCP? = nil) async throws -> [IPv4]
    {
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
        }
        else
        {
            sizeToSend = self.straw.count
        }

        var totalPayloadSize = 0
        var nextSequenceNumber = self.straw.sequenceNumber

        // We're trying to hit this limit exactly, but if we send to many packets at once they'll get discarded.
        // So try our best, but limit it to 3 packets max.
        while totalPayloadSize < sizeToSend, packets.count < 1
        {
            // Each packet is limited is by the amount left to send and the MTU (which we guess).
            let nextPacketSize = min(sizeToSend - totalPayloadSize, 1400)

            let window = SequenceNumberRange(lowerBound: nextSequenceNumber, size: UInt32(nextPacketSize))
            let packet = try await self.makeAck(window: window)
            packets.append(packet)

            totalPayloadSize = totalPayloadSize + nextPacketSize
            nextSequenceNumber = nextSequenceNumber.add(nextPacketSize)
        }

        return packets
    }

    func close() async throws
    {
        self.logger.trace("TcpStateHandler.close()")
        try await self.upstream.write(TcpProxyMessage.close.data)

        do
        {
            // This will probably throw since upstream will already have closed.
            try await self.upstream.close()
        }
        catch
        {
            return
        }
    }

    /// In all states except SYN-SENT, all reset (RST) segments are validated by checking their SEQ-fields.
    /// A reset is valid if its sequence number is in the window.
    ///
    /// The receiver of a RST first validates it, then changes state.
    func handleRstSynchronizedState(ipv4: IPv4, tcp: TCP) async throws -> TcpStateTransition
    {
        let packetLowerBound = SequenceNumber(tcp.sequenceNumber)
        var packetUpperBound = packetLowerBound
        
        guard self.straw.inWindow(tcp) else
        {
            self.logger.error("❌ handleRstSynchronizedState - sequenceNumber (\(packetLowerBound)) not in window")

            let ack = try await self.makeAck()
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
    
    func makeAck(window: SequenceNumberRange? = nil) async throws -> IPv4
    {
        if let window
        {
            let (_, acknowledgementNumber, windowSize) = self.getState()

//            self.logger.debug("TcpStateHandler.makeAck: \(window.lowerBound)..\(window.upperBound):\(window.size) - \(self.straw.sequenceNumber)..\(self.straw.sequenceNumber.add(window.size)):\(self.straw.count)")

            let segment = try self.straw.read(window: window)
            return try self.makePacket(sequenceNumber: segment.window.lowerBound, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize, ack: true, payload: segment.data)
        }
        else
        {
            let (sequenceNumber, acknowledgementNumber, windowSize) = self.getState()
            return try self.makePacket(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize, ack: true, payload: nil)
        }
    }
    
    func makeFin(window: SequenceNumberRange? = nil) async throws -> IPv4
    {
        if let window
        {
            let (_, acknowledgementNumber, windowSize) = self.getState()

//            self.logger.debug("TcpStateHandler.makeFin: \(window.lowerBound)..\(window.upperBound):\(window.size) - \(self.straw.sequenceNumber)..\(self.straw.sequenceNumber.add(window.size)):\(self.straw.count)")

            let segment = try self.straw.read(window: window)
            return try self.makePacket(sequenceNumber: segment.window.lowerBound, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize, fin: true)
        }
        else
        {
            let (sequenceNumber, acknowledgementNumber, windowSize) = self.getState()
            return try self.makePacket(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, windowSize: windowSize, fin: true)
        }
    }

    func makePacket(sequenceNumber: SequenceNumber, acknowledgementNumber: SequenceNumber, windowSize: UInt16, syn: Bool = false, ack: Bool = false, fin: Bool = false, rst: Bool = false, payload: Data? = nil) throws -> IPv4
    {
//        self.logger.trace("makePacket(sequenceNumber: \(sequenceNumber), acknowledgementNumber: \(acknowledgementNumber)")

        do
        {
//            self.logger.debug("TcpStateHandler - makePacket: Start")
//
//            self.logger.debug("TcpStateHandler - makePacket: Try to make an IPv4 Packet")
            guard let ipv4 = try IPv4(sourceAddress: self.identity.remoteAddress, destinationAddress: self.identity.localAddress, sourcePort: self.identity.remotePort, destinationPort: self.identity.localPort, sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, syn: syn, ack: ack, fin: fin, rst: rst, windowSize: windowSize, payload: payload) else
            {
                self.logger.debug("* sendPacket() failed to initialize IPv4 packet.")
                self.tcpLogger.debug("* sendPacket() failed to initialize IPv4 packet.")
                throw TcpProxyError.badIpv4Packet
            }
//            self.logger.debug("TcpStateHandler - makePacket: Made an IPv4 Packet!")

//            // Show the packet description in our log
//            if self.identity.remotePort == 2234 // Log traffic from the TCP Echo Server to the TCP log for debugging
//            {
//                let packet = Packet(ipv4Bytes: ipv4.data, timestamp: Date())
//
//                if let tcp = packet.tcp, tcp.syn, tcp.ack
//                {
//                    self.tcpLogger.debug("************************************************************\n")
//                    self.tcpLogger.debug("* ⬅ SYN/ACK SEQ:\(SequenceNumber(tcp.sequenceNumber)) ACK:\(SequenceNumber(tcp.acknowledgementNumber)) 💖")
//                    self.tcpLogger.debug("************************************************************\n")
//                }
//                else if let tcp = packet.tcp, tcp.ack, tcp.payload == nil
//                {
//                    self.tcpLogger.debug("************************************************************\n")
//                    self.tcpLogger.debug("* ⬅ ACK SEQ:\(SequenceNumber(tcp.sequenceNumber)) ACK:\(SequenceNumber(tcp.acknowledgementNumber)) 💖")
//                    self.tcpLogger.debug("************************************************************\n")
//                }
//                else if let tcp = packet.tcp, tcp.payload != nil
//                {
//                    self.tcpLogger.debug("************************************************************\n")
//                    self.tcpLogger.debug("* ⬅ ACK SEQ:\(SequenceNumber(tcp.sequenceNumber)) ACK:\(SequenceNumber(tcp.acknowledgementNumber)) 💖 📦")
//                    self.tcpLogger.debug("Payload size: \(tcp.payload!.count)")
//                    self.tcpLogger.debug("Payload:\n\(tcp.payload!.hex)")
//                    self.tcpLogger.debug("************************************************************\n")
//                }
//                else
//                {
//                    self.tcpLogger.debug("************************************************************\n")
//                    self.tcpLogger.debug("* \(packet.tcp?.description ?? "No tcp packet")")
//                    self.tcpLogger.debug("* Downstream IPv4 Packet created 💖")
//                    self.tcpLogger.debug("************************************************************\n")
//                }
//            }

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

