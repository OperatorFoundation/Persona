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
        let identity = try UdpIdentity(ipv4: ipv4, udp: udp)
        let upstream = try await UdpProxyConnection.getConnection(identity: identity, downstream: self.client, logger: self.logger, udpLogger: self.udpLogger, writeLogger: self.writeLogger)
        try await upstream.writeUpstream(ipv4: ipv4, udp: udp, payload: payload)

        if let result = try await upstream.readUpstream()
        {
            let (resultIPv4, resultUDP, resultPayload) = result

            self.logger.info("🏓 UDP: @ <- \(resultIPv4.sourceAddress.ipv4AddressString ?? "not an ipv4 address"):\(resultUDP.sourcePort) -> \(resultIPv4.destinationAddress.ipv4AddressString ?? "not an ipv4 address"):\(resultUDP.destinationPort) - \(resultPayload.count) byte payload")

            // We have a valid UDP packet, so we send it downstream to the client.
            // The client expects raw IPv4 packets prefixed with a 4-byte length.
            try await self.client.writeWithLengthPrefix(resultIPv4.data, 32)

            self.logger.debug("UDP: \(resultIPv4.sourceAddress.ipv4AddressString ?? "not an IPv4 address"):\(resultUDP.sourcePort) -> \(resultIPv4.destinationAddress.ipv4AddressString ?? "not an IPv4 address"):\(resultUDP.destinationPort) ; persona <- udpproxy: \(resultIPv4.data.count) bytes")
            if udp.destinationPort == 7
            {
                self.udpLogger.debug("UDP: \(resultIPv4.sourceAddress.ipv4AddressString ?? "not an IPv4 address"):\(resultUDP.sourcePort) -> \(resultIPv4.destinationAddress.ipv4AddressString ?? "not an IPv4 address"):\(resultUDP.destinationPort) ; persona <- udpproxy: \(resultIPv4.data.count) bytes")
            }
            self.writeLogger.info("\(resultIPv4.data.count) - \(resultIPv4.data.hex)")
        }
        else
        {
            self.logger.debug("UDP read upstream failed")
        }

        try await self.pump(upstream)
    }

    public func pump(_ skipConnection: UdpProxyConnection? = nil) async throws
    {
        for connection in UdpProxyConnection.getConnections()
        {
            let newIdentity = connection.identity

            if let skipConnection
            {
                let skipIdentity = skipConnection.identity

                if newIdentity == skipIdentity
                {
                    continue
                }
            }

            do
            {
                if let result = try await connection.pump()
                {
                    let (resultIPv4, resultUDP, resultPayload) = result

                    self.logger.info("🏓 UDP: $ <- \(resultIPv4.sourceAddress.ipv4AddressString ?? "not an ipv4 address"):\(resultUDP.sourcePort) -> \(resultIPv4.destinationAddress.ipv4AddressString ?? "not an ipv4 address"):\(resultUDP.destinationPort) - \(resultPayload.count) byte payload")

                    // We have a valid UDP packet, so we send it downstream to the client.
                    // The client expects raw IPv4 packets prefixed with a 4-byte length.
                    try await self.client.writeWithLengthPrefix(resultIPv4.data, 32)

                    self.logger.debug("UDP: \(resultIPv4.sourceAddress.ipv4AddressString ?? "not an IPv4 address"):\(resultUDP.sourcePort) -> \(resultIPv4.destinationAddress.ipv4AddressString ?? "not an IPv4 address"):\(resultUDP.destinationPort) ; persona <- udpproxy: \(resultIPv4.data.count) bytes")
                    if resultUDP.destinationPort == 7
                    {
                        self.udpLogger.debug("UDP: \(resultIPv4.sourceAddress.ipv4AddressString ?? "not an IPv4 address"):\(resultUDP.sourcePort) -> \(resultIPv4.destinationAddress.ipv4AddressString ?? "not an IPv4 address"):\(resultUDP.destinationPort) ; persona <- udpproxy: \(resultIPv4.data.count) bytes")
                    }
                    self.writeLogger.info("\(resultIPv4.data.count) - \(resultIPv4.data.hex)")
                }

                try await connection.checkForCleanup()
            }
            catch
            {
                self.logger.error("Error pumping UDP connection \(error)")

                continue
            }
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
