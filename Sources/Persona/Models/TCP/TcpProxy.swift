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
        // We need one udpproxy subsystem for each source address/port pair.
        // This is so we know how to route incoming traffic back to the client.
        let identity = try TcpIdentity(ipv4: ipv4, tcp: tcp)
        let (connection, isPrestablishedConnection) = try await TcpProxyConnection.getConnection(identity: identity, downstream: self.client, ipv4: ipv4, tcp: tcp, payload: payload, logger: logger, tcpLogger: tcpLogger, writeLogger: writeLogger)
        if isPrestablishedConnection
        {
            // Only process packets on preestablished connections. If it's a new connetion, it will process the packet internally in the constructor.
            try await connection.processDownstreamPacket(ipv4: ipv4, tcp: tcp, payload: payload)
        }

        await self.pump(connection)
    }

    // On every packet received, check on the OTHER connections.
    public func pump(_ skipConnection: TcpProxyConnection) async
    {
        let skipIdentity = skipConnection.identity

        for connection in TcpProxyConnection.getConnections()
        {
            let newIdentity = connection.identity

            if newIdentity == skipIdentity
            {
                continue
            }

            do
            {
                self.logger.trace("TcpProxy.pump starting - \(newIdentity)")
                try await connection.pump()
                self.logger.trace("TcpProxy.pump done - \(newIdentity)")
            }
            catch
            {
                self.logger.error("Error pumping connection \(error)")

                continue
            }
        }
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
