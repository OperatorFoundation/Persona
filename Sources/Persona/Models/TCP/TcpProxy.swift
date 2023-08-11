//
//  TcpProxy.swift
//
//
//  Created by Dr. Brandon Wiley on 3/7/22.
//

import Logging
import Foundation

import Chord
import InternetProtocols
import Net
import Puppy
import TransmissionAsync

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

    // An IPVv4-TCP packet has been received from the client. Check that we know how to handle it and then send it to the tcpproxy subsystem.
    public func processDownstreamPacket(ipv4: IPv4, tcp: TCP, payload: Data?) async throws
    {
        self.logger.debug("TcpProxy.processDownstreamPacket: \(ipv4.sourceAddress.ipv4AddressString ?? "not an IPv4 address"):\(tcp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "not an IPv4 address"):\(tcp.destinationPort)")
        if tcp.destinationPort == 7 || tcp.destinationPort == 853
        {
            self.tcpLogger.debug("TcpProxy.processDownstreamPacket: \(ipv4.sourceAddress.ipv4AddressString ?? "not an IPv4 address"):\(tcp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "not an IPv4 address"):\(tcp.destinationPort)")
        }

        // We need one udpproxy subsystem for each source address/port pair.
        // This is so we know how to route incoming traffic back to the client.
        let identity = try TcpIdentity(ipv4: ipv4, tcp: tcp)
        let connection = try await TcpProxyConnection.getConnection(identity: identity, downstream: self.client, ipv4: ipv4, tcp: tcp, payload: payload, logger: logger, tcpLogger: tcpLogger, writeLogger: writeLogger)
        try await connection.processDownstreamPacket(ipv4: ipv4, tcp: tcp, payload: payload)
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
}
