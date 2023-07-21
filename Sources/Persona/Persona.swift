//
//  Persona.swift
//
//
//  Created by Dr. Brandon Wiley on 2/24/22.
//
import FileLogging
import Logging
import Foundation

import Gardener
import InternetProtocols
import Puppy
import Net
import TransmissionAsync

public class Persona
{
    let connection: AsyncConnection

    let logger: Logger
    var tcpLogger = Puppy()

    var udpProxy: UdpProxy! = nil
    var tcpProxy: TcpProxy! = nil

    public init() throws
    {
        let mainLogURL = URL(fileURLWithPath: "/root/Persona/persona.log")
        self.logger = try FileLogging.logger(label: "Persona", localFile: mainLogURL)
        self.logger.info("Persona Start")

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

//        self.connection = AsyncSystemdConnection(logger)
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
                self.logger.debug("Persona.run reading next message")
                let message = try await self.connection.readWithLengthPrefix(prefixSizeInBits: 32)
                self.logger.debug("received \(message.count) bytes")
                try await self.handleMessage(message)
            }
            catch
            {
                self.logger.error("\(error.localizedDescription)")
                return
            }
        }
    }

    func handleMessage(_ data: Data) async throws
    {
        let packet = Packet(ipv4Bytes: data, timestamp: Date(), debugPrints: false)

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
