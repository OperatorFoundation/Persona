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

    static public func getConnection(identity: Identity, downstream: AsyncConnection, ipv4: IPv4, tcp: TCP, payload: Data?, logger: Logger, tcpLogger: Puppy, writeLogger: Puppy) async throws -> (TcpProxyConnection, Bool)
    {
        if let connection = Self.connections[identity]
        {
            return (connection, true)
        }
        else
        {
            guard tcp.syn, !tcp.ack, !tcp.rst, !tcp.fin else
            {
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

    public func processDownstreamPacket(ipv4: IPv4, tcp: TCP, payload: Data?) async throws
    {
        let tcpSequenceNumber = SequenceNumber(tcp.sequenceNumber)
        let tcpAcknowledgementNumber = SequenceNumber(tcp.acknowledgementNumber)
        let (sequenceNumber, acknowledgementNumber, _) = self.state.getState()
        let sequenceDifference = tcpSequenceNumber - acknowledgementNumber
        let acknowledgementDifference = tcpAcknowledgementNumber - sequenceNumber
        self.logger.debug("TcpProxyConnection.processDownstreamPacket - SEQ#:\(tcpSequenceNumber) (\(sequenceDifference) difference), ACK#:\(tcpAcknowledgementNumber) (\(acknowledgementDifference) difference)")

        let transition = try await self.state.processDownstreamPacket(ipv4: ipv4, tcp: tcp, payload: nil)

        var packetsToSend: [IPv4]
        
        switch transition.newState
        {
            case is TcpCloseWait:
                // Close Wait prep here
                let closeWaitTransition = try await transition.newState.pump()
                
                if transition.packetsToSend.count > 0
                {
                    let lastPacketIPv4 = transition.packetsToSend[transition.packetsToSend.endIndex - 1]
                    
                    let lastPacket = Packet(ipv4Bytes: lastPacketIPv4.data, timestamp: Date())
                    
                    if let lastPacketTCP = lastPacket.tcp
                    {
                        if let newLastPacketTCP = try TCP(sourcePort: lastPacketTCP.sourcePort, destinationPort: lastPacketTCP.destinationPort, sequenceNumber: SequenceNumber(lastPacketTCP.sequenceNumber), acknowledgementNumber: SequenceNumber(lastPacketTCP.acknowledgementNumber), syn: lastPacketTCP.syn, ack: lastPacketTCP.ack, fin: true, rst: lastPacketTCP.rst, windowSize: lastPacketTCP.windowSize, payload: lastPacketTCP.payload, ipv4: lastPacketIPv4)
                        {
                            if let newLastPacketIPv4 = IPv4(version: lastPacketIPv4.version, IHL: lastPacketIPv4.IHL, DSCP: lastPacketIPv4.DSCP, ECN: lastPacketIPv4.ECN, length: lastPacketIPv4.length, identification: lastPacketIPv4.identification, reservedBit: lastPacketIPv4.reservedBit, dontFragment: lastPacketIPv4.dontFragment, moreFragments: lastPacketIPv4.moreFragments, fragmentOffset: lastPacketIPv4.fragmentOffset, ttl: lastPacketIPv4.ttl, protocolNumber: lastPacketIPv4.protocolNumber, checksum: lastPacketIPv4.checksum, sourceAddress: lastPacketIPv4.sourceAddress, destinationAddress: lastPacketIPv4.destinationAddress, options: lastPacketIPv4.options, payload: newLastPacketTCP.data, ethernetPadding: lastPacketIPv4.ethernetPadding)
                            {
                                packetsToSend = transition.packetsToSend
                                
                                packetsToSend[transition.packetsToSend.endIndex - 1] = newLastPacketIPv4

                            }
                            else
                            {
                                packetsToSend = transition.packetsToSend + closeWaitTransition.packetsToSend
                            }
                        } else
                        {
                            packetsToSend = transition.packetsToSend + closeWaitTransition.packetsToSend
                        }
                    }
                    else
                    {
                        packetsToSend = transition.packetsToSend + closeWaitTransition.packetsToSend
                    }
                }
                else
                {
                    packetsToSend = transition.packetsToSend + closeWaitTransition.packetsToSend
                }
            
                self.logger.debug("@ \(self.state) => \(transition.newState) => \(closeWaitTransition.newState), \(packetsToSend.count) packets to send")
                self.state = closeWaitTransition.newState
                
            default:
                // Nothing to do here
                packetsToSend = transition.packetsToSend
                self.logger.debug("@ \(self.state) => \(transition.newState), \(packetsToSend.count) packets to send")
                self.state = transition.newState
        }
        
        for packet in packetsToSend
        {
            let outPacket = Packet(ipv4Bytes: packet.data, timestamp: Date())
            if let outTcp = outPacket.tcp
            {
                self.logger.debug("@ <- \(description(packet, outTcp))")

                if outTcp.sourcePort == 7
                {
                    self.tcpLogger.debug("@ <- \(description(packet, outTcp))")
                }
            }

            self.logger.trace("About to send packet.")
            try await self.sendPacket(packet)
            self.logger.trace("Sent packet.")
        }

        guard self.state.open else
        {
            self.logger.debug("TcpProxyConnection.processDownstreamPacket - connection was closed")
            if tcp.destinationPort == 7 || tcp.destinationPort == 853
            {
                self.tcpLogger.debug("TcpProxyConnection.processDownstreamPacket - connection was closed")
            }

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

    public func processUpstreamData(data: Data) async throws
    {
        let transition = try await self.state.processUpstreamData(data: data)

        for packet in transition.packetsToSend
        {
            let outPacket = Packet(ipv4Bytes: packet.data, timestamp: Date())
            if let outTcp = outPacket.tcp
            {
                self.logger.debug("$ <- \(description(packet, outTcp))")

                if outTcp.sourcePort == 7
                {
                    self.tcpLogger.debug("$ <- \(description(packet, outTcp))")
                }
            }

            try await self.sendPacket(packet)
        }

        self.state = transition.newState

        guard self.state.open else
        {
            self.logger.debug("TcpProxyConnection.pump - connection was closed")

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
            self.writeLogger.info("TcpProxyConnection.sendPacket - write \(ipv4.data.count) bytes to client")

            self.logger.debug("<<- \(description(ipv4, tcp))")

            let clientMessage = Data(array: [Subsystem.Client.rawValue]) + ipv4.data
            try await self.downstream.writeWithLengthPrefix(clientMessage, 32)

            self.writeLogger.info("TcpProxyConnection.sendPacket - succesfully wrote \(ipv4.data.count) bytes to client")
        }
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
