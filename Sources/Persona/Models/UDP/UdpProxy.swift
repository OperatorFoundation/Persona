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
    static public let udpTimeout: TimeInterval = 1 * 60 // 1 minute, in seconds

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
