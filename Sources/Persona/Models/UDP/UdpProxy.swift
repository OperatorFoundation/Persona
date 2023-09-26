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

// Persona's UDP proxying control logic offloads UDP packets to the udpproxy subsystem.
// This control logic filters out packets that we don't know how to handle and prepares them into a form suitable for ingestion by the updproxy subsystem.
// It also receives output from the udpproxy subsystem and prepares it into a form suitable for sending back to the client.
public class UdpProxy
{
    // UDP connections never explictly close, so we time them out eventually.
    static public let udpTimeout: TimeInterval = 5 // 5 seconds

    let client: AsyncConnection
    let logger: Logger
    let udpLogger: Puppy
    let writeLogger: Puppy

    public init(client: AsyncConnection, logger: Logger, udpLogger: Puppy, writeLogger: Puppy) async throws
    {
        self.client = client
        self.logger = logger
        self.udpLogger = udpLogger
        self.writeLogger = writeLogger
    }

    public func handleMessage(_ message: Data) async throws
    {

    }

    // An IPVv4-UDP packet has been received from the client. Check that we know how to handle it and then send it to the udpproxy subsystem.
    public func processDownstreamPacket(ipv4: IPv4, udp: UDP, payload: Data) async throws
    {
//        self.logger.debug("UdpProxy.processDownstreamPacket: \(ipv4.sourceAddress.ipv4AddressString ?? "not an IPv4 address"):\(udp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "not an IPv4 address"):\(udp.destinationPort)")
//        if udp.destinationPort == 7
//        {
//            self.udpLogger.debug("UdpProxy.processDownstreamPacket: \(ipv4.sourceAddress.ipv4AddressString ?? "not an IPv4 address"):\(udp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "not an IPv4 address"):\(udp.destinationPort)")
//        }

        // We need one udpproxy subsystem for each source address/port pair.
        // This is so we know how to route incoming traffic back to the client.
        let identity = try Identity(ipv4: ipv4, udp: udp)
        let upstream = try await UdpProxyConnection.getConnection(identity: identity, downstream: self.client, logger: self.logger, udpLogger: self.udpLogger, writeLogger: self.writeLogger)
        try await upstream.writeUpstream(ipv4: ipv4, udp: udp, payload: payload)

        if let result = try await upstream.readUpstream()
        {
            let (resultIPv4, resultUDP, resultPayload) = result

            self.logger.info("🏓 UDP: @ <- \(resultIPv4.sourceAddress.ipv4AddressString ?? "not an ipv4 address"):\(resultUDP.sourcePort) -> \(resultIPv4.destinationAddress.ipv4AddressString ?? "not an ipv4 address"):\(resultUDP.destinationPort) - \(resultPayload.count) byte payload")

            // We have a valid UDP packet, so we send it downstream to the client.
            // The client expects raw IPv4 packets prefixed with a 4-byte length.
            let clientMessage = Data(array: [Subsystem.Client.rawValue]) + resultIPv4.data
            try await self.client.writeWithLengthPrefix(clientMessage, 32)

            self.logger.debug("UDP: \(resultIPv4.sourceAddress.ipv4AddressString ?? "not an IPv4 address"):\(resultUDP.sourcePort) -> \(resultIPv4.destinationAddress.ipv4AddressString ?? "not an IPv4 address"):\(resultUDP.destinationPort) ; persona <- udpproxy: \(resultIPv4.data.count) bytes")
            if udp.destinationPort == 7
            {
                self.udpLogger.debug("UDP: \(resultIPv4.sourceAddress.ipv4AddressString ?? "not an IPv4 address"):\(resultUDP.sourcePort) -> \(resultIPv4.destinationAddress.ipv4AddressString ?? "not an IPv4 address"):\(resultUDP.destinationPort) ; persona <- udpproxy: \(resultIPv4.data.count) bytes")
            }
            self.writeLogger.info("\(resultIPv4.data.count)")
        }
        else
        {
            self.logger.debug("UDP read upstream failed")
        }
    }

    public func pump(_ skipConnection: UdpProxyConnection? = nil) async throws -> Bool
    {
        guard let connection = UdpProxyConnection.getQueuedConnection() else
        {
            return false
        }

        let newIdentity = connection.identity

        if let skipConnection
        {
            let skipIdentity = skipConnection.identity

            if newIdentity == skipIdentity
            {
                return false
            }
        }

        if let result = try await connection.pump()
        {
            let (resultIPv4, resultUDP, resultPayload) = result

            self.logger.info("🏓 UDP: $ <- \(resultIPv4.sourceAddress.ipv4AddressString ?? "not an ipv4 address"):\(resultUDP.sourcePort) -> \(resultIPv4.destinationAddress.ipv4AddressString ?? "not an ipv4 address"):\(resultUDP.destinationPort) - \(resultPayload.count) byte payload")

            // We have a valid UDP packet, so we send it downstream to the client.
            // The client expects raw IPv4 packets prefixed with a 4-byte length.
            let clientMessage = Data(array: [Subsystem.Client.rawValue]) + resultIPv4.data
            try await self.client.writeWithLengthPrefix(clientMessage, 32)

            self.logger.debug("UDP: \(resultIPv4.sourceAddress.ipv4AddressString ?? "not an IPv4 address"):\(resultUDP.sourcePort) -> \(resultIPv4.destinationAddress.ipv4AddressString ?? "not an IPv4 address"):\(resultUDP.destinationPort) ; persona <- udpproxy: \(resultIPv4.data.count) bytes")
            if resultUDP.destinationPort == 7
            {
                self.udpLogger.debug("UDP: \(resultIPv4.sourceAddress.ipv4AddressString ?? "not an IPv4 address"):\(resultUDP.sourcePort) -> \(resultIPv4.destinationAddress.ipv4AddressString ?? "not an IPv4 address"):\(resultUDP.destinationPort) ; persona <- udpproxy: \(resultIPv4.data.count) bytes")
            }
            self.writeLogger.info("\(resultIPv4.data.count)")

            try await connection.checkForCleanup()

            return true
        }
        else
        {
            try await connection.checkForCleanup()

            return false
        }
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
}
