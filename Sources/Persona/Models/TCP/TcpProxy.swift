//
//  TcpProxy.swift
//
//
//  Created by Dr. Brandon Wiley on 3/7/22.
//

import Logging
import Foundation

import Chord
import Datable
import InternetProtocols
import Net
import Puppy
import TransmissionAsync

public enum TcpProxyRequestType: UInt8, CustomStringConvertible
{
    public var description: String
    {
        switch self
        {
            case .RequestOpen:
                return "OPEN"

            case .RequestWrite:
                return "WRITE"

            case .RequestClose:
                return "CLOSE"
        }
    }

    case RequestOpen = 1
    case RequestWrite = 2
    case RequestClose = 3
}

public struct TcpProxyRequest: CustomStringConvertible
{
    public var description: String
    {
        if let payload = self.payload
        {
            return "[TCP Request \(self.type): \(self.identity), \(payload.count) bytes]"
        }
        else
        {
            return "[TCP Request \(self.type): \(self.identity)]"
        }
    }

    public var data: Data
    {
        let typeBytes = Data(array: [Subsystem.Tcpproxy.rawValue, self.type.rawValue])
        let identityBytes = self.identity.data

        if let payload = self.payload
        {
            return typeBytes + identityBytes + payload
        }
        else
        {
            return typeBytes + identityBytes
        }
    }

    let type: TcpProxyRequestType
    let identity: Identity
    let payload: Data?

    public init(type: TcpProxyRequestType, identity: Identity, payload: Data? = nil)
    {
        self.type = type
        self.identity = identity
        self.payload = payload
    }
}

public enum TcpProxyResponseType: UInt8, CustomStringConvertible
{
    public var description: String
    {
        switch self
        {
            case .ResponseData:
                return "DATA"

            case .ResponseClose:
                return "CLOSE"

            case .ResponseError:
                return "ERROR"

            case .ResponseConnectSuccess:
                return "SUCCESS"

            case .ResponseConnectFailure:
                return "FAILURE"
        }
    }

    case ResponseData = 1
    case ResponseClose = 2
    case ResponseError = 3
    case ResponseConnectSuccess = 4
    case ResponseConnectFailure = 5
}

public struct TcpProxyResponse: CustomStringConvertible
{
    public var description: String
    {
        if let payload = self.payload
        {
            return "[TCP Response \(self.type): \(self.identity), \(payload.count) bytes]"
        }
        else
        {
            if let error = self.error
            {
                return "[TCP Response \(self.type): \(self.identity), \(error.localizedDescription)]"
            }
            else
            {
                return "[TCP Response \(self.type): \(self.identity)]"
            }
        }
    }

    let type: TcpProxyResponseType
    let identity: Identity
    let payload: Data?
    let error: Error?

    public init(type: TcpProxyResponseType, identity: Identity, payload: Data? = nil, error: Error? = nil)
    {
        self.type = type
        self.identity = identity
        self.payload = payload
        self.error = error
    }

    public init(data: Data) throws
    {
        guard data.count >= 13 else
        {
            throw TcpProxyError.shortMessage
        }

        let typeByte = data[0]
        let identityBytes = Data(data[1..<13])
        let rest = Data(data[13...])

        guard let type = TcpProxyResponseType(rawValue: typeByte) else
        {
            throw TcpProxyError.badMessage
        }

        let identity = try Identity(data: identityBytes)

        switch type
        {
            case .ResponseData:
                self.init(type: type, identity: identity, payload: rest)

            case .ResponseClose:
                self.init(type: type, identity: identity)

            case .ResponseError:
                self.init(type: type, identity: identity, error: TcpProxyError.frontendError(rest.string))

            case .ResponseConnectSuccess:
                self.init(type: type, identity: identity)

            case .ResponseConnectFailure:
                self.init(type: type, identity: identity)
        }
    }
}

// Persona's TCP proxying control logic offloads TCP packets to the tcpproxy subsystem.
// This control logic filters out packets that we don't know how to handle and prepares them into a form suitable for ingestion by the tcpproxy subsystem.
// It also receives output from the tcpproxy subsystem and prepares it into a form suitable for sending back to the client.
public actor TcpProxy
{
    let client: AsyncConnection
    let logger: Logger
    let tcpLogger: Puppy
    let writeLogger: Puppy

    public init(client: AsyncConnection, logger: Logger, tcpLogger: Puppy, writeLogger: Puppy)
    {
        self.client = client
        self.logger = logger
        self.tcpLogger = tcpLogger
        self.writeLogger = writeLogger
    }

    public func handleMessage(_ data: Data) async throws
    {
        let message = try TcpProxyResponse(data: data)
        self.logger.info(">> \(message)")
        switch message.type
        {
            case .ResponseData:
                guard let data = message.payload else
                {
                    throw TcpProxyError.badMessage
                }

                try await self.processUpstreamData(identity: message.identity, data: data)

            case .ResponseClose:
                try await self.processUpstreamClose(identity: message.identity)

            case .ResponseError:
                self.logger.error("TcpProxy.handleMessage - error: \(message.error?.localizedDescription ?? "none")")

            case .ResponseConnectSuccess:
                try await self.processUpstreamConnectSuccess(identity: message.identity)

            case .ResponseConnectFailure:
                try await self.processUpstreamConnectFailure(identity: message.identity)
        }
    }

    // An IPVv4-TCP packet has been received from the client. Check that we know how to handle it and then send it to the tcpproxy subsystem.
    public func processDownstreamPacket(ipv4: IPv4, tcp: TCP, payload: Data?) async throws
    {
        // We need one udpproxy subsystem for each source address/port pair.
        // This is so we know how to route incoming traffic back to the client.
        let identity = try Identity(ipv4: ipv4, tcp: tcp)
        let (connection, isPrestablishedConnection) = try await TcpProxyConnection.getConnection(identity: identity, downstream: self.client, ipv4: ipv4, tcp: tcp, payload: payload, logger: logger, tcpLogger: tcpLogger, writeLogger: writeLogger)
        if isPrestablishedConnection
        {
            // Only process packets on preestablished connections. If it's a new connetion, it will process the packet internally in the constructor.
            try await connection.processDownstreamPacket(ipv4: ipv4, tcp: tcp, payload: payload)
        }
    }

    public func processUpstreamConnectSuccess(identity: Identity) async throws
    {
        let connection = try TcpProxyConnection.getConnection(identity: identity)

        try await connection.processUpstreamConnectSuccess()

        let (ipv4, tcp, payload) = connection.firstPacket
        try await connection.processDownstreamPacket(ipv4: ipv4, tcp: tcp, payload: payload)
    }

    public func processUpstreamConnectFailure(identity: Identity) async throws
    {
        let connection = try TcpProxyConnection.getConnection(identity: identity)

        try await connection.processUpstreamConnectFailure()
    }

    public func processUpstreamData(identity: Identity, data: Data) async throws
    {
        let connection = try TcpProxyConnection.getConnection(identity: identity)

        try await connection.processUpstreamData(data: data)
    }

    public func processUpstreamClose(identity: Identity) async throws
    {
        try await TcpProxyConnection.close(identity: identity)
    }
}

public enum TcpProxyError: Error
{
    case upstreamConnectionFailed
    case unknownConnectionStatus(UInt8)
    case addressMismatch(String, String)
    case invalidAddress(Data)
    case notIPv4Packet(Packet)
    case notTcpPacket(Packet)
    case badIpv4Packet
    case dataConversionFailed
    case shortMessage
    case badMessage
    case frontendError(String)
    case badIdentity
}
