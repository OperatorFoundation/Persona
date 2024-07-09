//
//  TcpProxyConnection.swift
//  
//
//  Created by Dr. Brandon Wiley on 3/11/22.
//
import Foundation
import Logging

import Chord
import InternetProtocols
import Net
import Puppy
import SwiftHexTools
import TransmissionAsync

public actor TcpProxyConnection
{
    // These static properties and functions handle caching connections to the tcpproxy subsystem.
    // We need one connection to the tcpproxy subsystem for each source address/port pair.
    static var connections: [Identity: TcpProxyConnection] = [:]
    static var queue: [Identity] = []

    static public func getConnection(identity: Identity) throws -> TcpProxyConnection
    {
        guard let connection = Self.connections[identity] else
        {
            throw TcpProxyConnectionError.unknownConnection
        }

        return connection
    }

    static public func getConnection(identity: Identity, downstream: AsyncConnection, ipv4: IPv4, tcp: TCP, payload: Data?, logger: Logger, tcpLogger: Puppy, writeLogger: Puppy, stats: Stats) async throws -> (TcpProxyConnection, Bool)
    {
        if let connection = Self.connections[identity]
        {
            return (connection, true)
        }
        else
        {
            guard tcp.syn, !tcp.ack, !tcp.rst, !tcp.fin else
            {
                if !tcp.syn
                {
                    stats.firstPacketNotSyn += 1
                }
                
                if tcp.ack
                {
                    stats.firstPacketAck += 1
                }
                
                if tcp.rst
                {
                    stats.firstPacketRst += 1
                }
                
                if tcp.fin
                {
                    stats.firstPacketFin += 1
                }
                
                throw TcpProxyConnectionError.badFirstPacket
            }

            let connection = try await TcpProxyConnection(identity: identity, downstream: downstream, ipv4: ipv4, tcp: tcp, payload: payload, logger: logger, tcpLogger: tcpLogger, writeLogger: writeLogger)
            Self.connections[identity] = connection
            Self.queue.append(identity)
            
            return (connection, false)
        }
    }

    static public func removeConnection(identity: Identity)
    {
        self.connections.removeValue(forKey: identity)
        self.queue = self.queue.filter
        {
            queueIdentity in

            return queueIdentity != identity
        }
    }

    static public func getConnections() -> [TcpProxyConnection]
    {
        return [TcpProxyConnection](self.connections.values)
    }

    static public func getQueuedConnection() -> TcpProxyConnection?
    {
        guard self.queue.count > 0 else
        {
            return nil
        }

        let identity = self.queue.removeFirst()
        let connection = self.connections[identity]
        if connection != nil
        {
            self.queue.append(identity)
        }

        return connection
    }

    static public func close(identity: Identity) async throws
    {
        if let connection = self.connections[identity]
        {
            try await connection.state.close()
        }
    }
    // End of static section

    public let identity: Identity
    public let firstPacket: (IPv4, TCP, Data?)

    let downstream: AsyncConnection
    let logger: Logger
    let tcpLogger: Puppy
    let writeLogger: Puppy

    // https://flylib.com/books/en/3.223.1.188/1/
    var state: TcpStateHandler

    // init() automatically send a syn-ack back for the syn (we only open a connect on receiving a syn)
    public init(identity: Identity, downstream: AsyncConnection, ipv4: IPv4, tcp: TCP, payload: Data?, logger: Logger, tcpLogger: Puppy, writeLogger: Puppy) async throws
    {
        self.identity = identity
        self.downstream = downstream
        self.logger = logger
        self.tcpLogger = tcpLogger
        self.writeLogger = writeLogger
        self.firstPacket = (ipv4, tcp, payload)

        let message = TcpProxyRequest(type: .RequestOpen, identity: self.identity, payload: payload)
        self.logger.debug("<< \(message)")
        try await self.downstream.writeWithLengthPrefix(message.data, 32)

        self.state = TcpNew(identity: identity, downstream: downstream, logger: logger, tcpLogger: tcpLogger, writeLogger: writeLogger)
    }

    public func processDownstreamPacket(stats: Stats, ipv4: IPv4, tcp: TCP, payload: Data?) async throws
    {
        let tcpSequenceNumber = SequenceNumber(tcp.sequenceNumber)
        let tcpAcknowledgementNumber = SequenceNumber(tcp.acknowledgementNumber)
        let (sequenceNumber, acknowledgementNumber, _) = self.state.getState()
        let sequenceDifference = tcpSequenceNumber - acknowledgementNumber
        let acknowledgementDifference = tcpAcknowledgementNumber - sequenceNumber

        #if DEBUG
        self.logger.debug("TcpProxyConnection.processDownstreamPacket - SEQ#:\(tcpSequenceNumber) (\(sequenceDifference) difference), ACK#:\(tcpAcknowledgementNumber) (\(acknowledgementDifference) difference)")
        #endif

        let transition = try await self.state.processDownstreamPacket(stats: stats, ipv4: ipv4, tcp: tcp, payload: nil)
        let packetsToSend: [IPv4] = transition.packetsToSend

        #if DEBUG
        self.logger.debug("@ \(self.state) => \(transition.newState), \(packetsToSend.count) packets to send")
        #endif

        self.state = transition.newState
        
        for packet in packetsToSend
        {
            let outPacket = Packet(ipv4Bytes: packet.data, timestamp: Date())
            if let outTcp = outPacket.tcp
            {
                #if DEBUG
                self.logger.debug("@ <- \(description(packet, outTcp))")
                #endif
            }

            try await self.sendPacket(packet)
        }

        guard self.state.open else
        {
            #if DEBUG
            self.logger.debug("TcpProxyConnection.processDownstreamPacket - connection was closed")
            #endif

            do
            {
                try await self.state.close()
            }
            catch
            {
                self.logger.error("TcpProxyConnection.processDownstreamPacket - Tried to close connection that was already closed \(error)")
            }

            Self.removeConnection(identity: self.identity)

            throw TcpProxyConnectionError.tcpClosed
        }
    }

    public func processUpstreamConnectSuccess() async throws
    {
        let transition = try await self.state.processUpstreamConnectSuccess()
        self.state = transition.newState

        for packet in transition.packetsToSend
        {
            try await self.sendPacket(packet)
        }
    }

    public func processUpstreamConnectFailure() async throws
    {
        let transition = try await self.state.processUpstreamConnectFailure()
        self.state = transition.newState

        for packet in transition.packetsToSend
        {
            try await self.sendPacket(packet)
        }
    }

    public func processUpstreamData(stats: Stats, data: Data) async throws
    {
        let transition = try await self.state.processUpstreamData(stats: stats, data: data)

        for packet in transition.packetsToSend
        {
            let outPacket = Packet(ipv4Bytes: packet.data, timestamp: Date())
            if let outTcp = outPacket.tcp
            {
                #if DEBUG
                self.logger.debug("$ <- \(description(packet, outTcp))")
                #endif
            }

            try await self.sendPacket(packet)
        }

        self.state = transition.newState

        guard self.state.open else
        {
            #if DEBUG
            self.logger.debug("TcpProxyConnection.pump - connection was closed")
            #endif

            do
            {
                try await self.state.close()
            }
            catch
            {
                self.logger.error("TcpProxyConnection.pump - Tried to close connection that was already closed")
            }

            Self.removeConnection(identity: self.identity)

            throw TcpProxyConnectionError.tcpClosed
        }
    }

    public func processTimeout(stats: Stats, lowerBound: SequenceNumber) async throws
    {
        guard let packet = try? await self.state.processTimeout(stats: stats, lowerBound: lowerBound) else
        {
            // The segment for this timeout has already been cleared from the retransmission queue.
            // Do nothing.
            return
        }

        // Retransmit the segment
        let outPacket = Packet(ipv4Bytes: packet.data, timestamp: Date())
        if let outTcp = outPacket.tcp
        {
            #if DEBUG
            self.logger.debug("$ <-R \(description(packet, outTcp))")
            #endif
        }

        try await self.sendPacket(packet)
    }

    func close() async throws
    {
        try await self.state.close()
        Self.removeConnection(identity: self.identity)
    }

    func sendPacket(_ ipv4: IPv4) async throws
    {
        let packet = Packet(ipv4Bytes: ipv4.data, timestamp: Date())
        if let ipv4 = packet.ipv4, let tcp = packet.tcp
        {
            #if DEBUG
            self.logger.debug("<<- \(description(ipv4, tcp))")
            #endif

            let clientMessage = Data(array: [Subsystem.Client.rawValue]) + ipv4.data
            try await self.downstream.writeWithLengthPrefix(clientMessage, 32)

            if tcp.payload != nil
            {
                let sequenceNumber = SequenceNumber(data: tcp.sequenceNumber)
                
                try await self.setTimeout(sequenceNumber)
            }
        }
    }

    func setTimeout(_ sequenceNumber: SequenceNumber) async throws
    {
        let request = TcpProxyTimerRequest(identity: self.identity, sequenceNumber: sequenceNumber)

        #if DEBUG
        self.logger.debug("<<-🕕 \(request.description)")
        #endif

        try await self.downstream.writeWithLengthPrefix(request.data, 32)
    }
}

public enum ConnectionStatus: UInt8
{
    case success = 0xF1
    case failure = 0xF0
}

public enum TcpProxyConnectionError: Error
{
    case badFirstPacket
    case tcpClosed
    case unknownConnection
}
