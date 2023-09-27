//
//  UdpProxy.swift
//
//
//  Created by Dr. Brandon Wiley on 3/7/22.
//

import Logging
import Foundation

import InternetProtocols
import Puppy
import Net
import TransmissionAsync

public enum UdpProxyRequestType: UInt8, CustomStringConvertible
{
    public var description: String
    {
        switch self
        {
            case .RequestWrite:
                return "WRITE"
        }
    }

    case RequestWrite = 2
}

public struct UdpProxyRequest: CustomStringConvertible
{
    public var description: String
    {
        if let payload = self.payload
        {
            return "[UDP Request \(self.type): \(self.identity), \(payload.count) bytes]"
        }
        else
        {
            return "[UDP Request \(self.type): \(self.identity)]"
        }
    }

    public var data: Data
    {
        let typeBytes = Data(array: [Subsystem.Udpproxy.rawValue, self.type.rawValue])
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

    let type: UdpProxyRequestType
    let identity: Identity
    let payload: Data?

    public init(type: UdpProxyRequestType, identity: Identity, payload: Data? = nil)
    {
        self.type = type
        self.identity = identity
        self.payload = payload
    }
}

public enum UdpProxyResponseType: UInt8, CustomStringConvertible
{
    public var description: String
    {
        switch self
        {
            case .ResponseData:
                return "DATA"

            case .ResponseError:
                return "ERROR"
        }
    }

    case ResponseData = 1
    case ResponseError = 3
}

public struct UdpProxyResponse: CustomStringConvertible
{
    public var description: String
    {
        if let payload = self.payload
        {
            return "[UDP Response \(self.type): \(self.identity), \(payload.count) bytes]"
        }
        else
        {
            if let error = self.error
            {
                return "[UDP Response \(self.type): \(self.identity), \(error.localizedDescription)]"
            }
            else
            {
                return "[UDP Response \(self.type): \(self.identity)]"
            }
        }
    }

    let type: UdpProxyResponseType
    let identity: Identity
    let payload: Data?
    let error: Error?

    public init(type: UdpProxyResponseType, identity: Identity, payload: Data? = nil, error: Error? = nil)
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
            throw UdpProxyError.shortMessage
        }

        let typeByte = data[0]
        let identityBytes = Data(data[1..<13])
        let rest = Data(data[13...])

        guard let type = UdpProxyResponseType(rawValue: typeByte) else
        {
            throw UdpProxyError.badMessage
        }

        let identity = try Identity(data: identityBytes)

        switch type
        {
            case .ResponseData:
                self.init(type: type, identity: identity, payload: rest)

            case .ResponseError:
                self.init(type: type, identity: identity, error: UdpProxyError.frontendError(rest.string))
        }
    }
}

// Persona's UDP proxying control logic offloads UDP packets to the udpproxy subsystem.
// This control logic filters out packets that we don't know how to handle and prepares them into a form suitable for ingestion by the updproxy subsystem.
// It also receives output from the udpproxy subsystem and prepares it into a form suitable for sending back to the client.
public class UdpProxy
{
    // UDP connections never explictly close, so we time them out eventually.
    static public let udpTimeout: TimeInterval = 5 // 5 seconds

    let downstream: AsyncConnection
    let logger: Logger
    let udpLogger: Puppy
    let writeLogger: Puppy

    public init(client: AsyncConnection, logger: Logger, udpLogger: Puppy, writeLogger: Puppy) async throws
    {
        self.downstream = client
        self.logger = logger
        self.udpLogger = udpLogger
        self.writeLogger = writeLogger
    }

    public func handleMessage(_ data: Data) async throws
    {
        let message = try UdpProxyResponse(data: data)

        #if DEBUG
        self.logger.debug(">> \(message)")
        #endif

        switch message.type
        {
            case .ResponseData:
                guard let data = message.payload else
                {
                    throw UdpProxyError.badMessage
                }

                try await self.processUpstreamData(identity: message.identity, data: data)

            case .ResponseError:
                self.logger.error("UdpProxy.handleMessage - error: \(message.error?.localizedDescription ?? "none")")
        }
    }

    // An IPVv4-UDP packet has been received from the client. Check that we know how to handle it and then send it to the udpproxy subsystem.
    public func processDownstreamPacket(ipv4: IPv4, udp: UDP, payload: Data) async throws
    {
        // We need one udpproxy subsystem for each source address/port pair.
        // This is so we know how to route incoming traffic back to the client.
        let identity = try Identity(ipv4: ipv4, udp: udp)
        let message = UdpProxyRequest(type: .RequestWrite, identity: identity, payload: payload)

        self.logger.debug("<< UDP \(message)")
        try await self.downstream.writeWithLengthPrefix(message.data, 32)
    }

    public func processUpstreamData(identity: Identity, data: Data) async throws
    {
        guard data.count > 0 else
        {
            return
        }

        // Here we do NAT translation on the UDP layer, adding the stored destination port.
        // This is why we need one udpproxy instance per address/port pair.
        guard let udp = InternetProtocols.UDP(sourcePort: identity.remotePort, destinationPort: identity.localPort, payload: data) else
        {
            self.logger.error("UdpProxyConnection.processRemoteData - failed to make a UDP packet")
            return
        }

        // Here we do NAT translation on the IPv4 layer, adding the stored destination address.
        // This is why we need one udpproxy instance per address/port pair.
        guard let ipv4 = try InternetProtocols.IPv4(sourceAddress: identity.remoteAddress, destinationAddress: identity.localAddress, payload: udp.data, protocolNumber: InternetProtocols.IPprotocolNumber.UDP) else
        {
            self.logger.error("UdpProxyConnection.processRemoteData - failed to make a IPv4 packet")
            return
        }

        #if DEBUG
        self.logger.debug("<<- UDP \(ipv4.sourceAddress.ipv4AddressString ?? "not an ipv4 address"):\(udp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "not an ipv4 address"):\(udp.destinationPort) - \(data.count) byte payload")
        #endif

        // We have a valid UDP packet, so we send it downstream to the client.
        // The client expects raw IPv4 packets prefixed with a 4-byte length.
        let message = Data(array: [Subsystem.Client.rawValue]) + ipv4.data

        try await self.downstream.writeWithLengthPrefix(message, 32)
    }
}

public enum UdpProxyError: Error
{
    case addressMismatch(String, String)
    case invalidAddress(Data)
    case notIPv4Packet(Packet)
    case notUdpPacket(Packet)
    case dataConversionFailed
    case badUdpProxyResponse
    case frontendError(String)
    case badMessage
    case shortMessage
}
