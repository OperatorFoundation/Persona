//
//  Persona.swift
//
//
//  Created by Dr. Brandon Wiley on 2/24/22.
//
#if os(macOS) || os(iOS)
import os.log
#else
import Logging
#endif
import Foundation

import Gardener
import InternetProtocols
import KeychainCli
import Puppy
import Net
import TransmissionAsync

public class Persona
{
    let connection: AsyncConnection

    var tcpLogger = Puppy()

    var udpProxy: UdpProxy! = nil
    var tcpProxy: TcpProxy! = nil

    public init()
    {
#if os(macOS) || os(iOS)
        let logger = Logger(subsystem: "org.OperatorFoundation.PersonaLogger", category: "Persona")
#else
        let logger = Logger(label: "org.OperatorFoundation.PersonaLogger")
#endif

        let logFileURL = File.homeDirectory().appendingPathComponent("PersonaTcpLog.log", isDirectory: false)

        if File.exists(logFileURL.path)
        {
            let _ = File.delete(atPath: logFileURL.path)
        }

        if let file = try? FileLogger("PersonaTCPLogger",
                                      logLevel: .debug,
                                      fileURL: logFileURL,
                                      filePermission: "600")  // Default permission is "640".
        {
            tcpLogger.add(file)
        }

        tcpLogger.debug("PersonaTCPLogger Start")

        self.connection = AsyncStdioConnection(logger)

        self.udpProxy = UdpProxy(client: self.connection)
        self.tcpProxy = TcpProxy(client: self.connection, quietTime: false, logger: logger, tcpLogger: tcpLogger)
    }

    public func run() async throws
    {
        while true
        {
            do
            {
                let message = try await self.connection.readWithLengthPrefix(prefixSizeInBits: 32)
                try await self.handleMessage(message)
            }
            catch
            {
                continue
            }
        }
    }

    func handleMessage(_ data: Data) async throws
    {
        let packet = Packet(ipv4Bytes: data, timestamp: Date(), debugPrints: true)

        if packet.tcp != nil
        {
            try await self.tcpProxy.processUpstreamPacket(packet)
        }
        else if let udp = packet.udp
        {
            guard udp.payload != nil else
            {
                throw PersonaError.emptyPayload
            }

            try self.udpProxy.processLocalPacket(packet)
        }
    }
}

public enum PersonaError: Error
{
    case addressPoolAllocationFailed
    case addressStringIsNotIPv4(String)
    case addressDataIsNotIPv4(Data)
    case connectionClosed
    case packetNotIPv4(Data)
    case unsupportedPacketType(Data)
    case emptyPayload
    case echoListenerFailure
    case listenFailed
}
