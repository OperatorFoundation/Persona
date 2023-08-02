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
    var udpLogger = Puppy()
    var packetLogger = Puppy()
    var clientWriteLog = Puppy()

    var udpProxy: UdpProxy! = nil
    var tcpProxy: TcpProxy! = nil

    public init() throws
    {
        let mainLogURL = URL(fileURLWithPath: "/root/Persona/persona.log")
        self.logger = try FileLogging.logger(label: "Persona", localFile: mainLogURL)
        self.logger.info("Persona Start")

        let logFileURL = File.homeDirectory().appendingPathComponent("Persona/PersonaTcpLog.log", isDirectory: false)
        let logFileURL2 = File.homeDirectory().appendingPathComponent("Persona/PersonaUdpLog.log", isDirectory: false)
        let logFileURL3 = File.homeDirectory().appendingPathComponent("Persona/PersonaPacketLog.log", isDirectory: false)
        let logFileURL4 = File.homeDirectory().appendingPathComponent("Persona/PersonaClientWriteLog.log", isDirectory: false)

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

        if let file2 = try? FileLogger("PersonaUDPLogger",
                                      logLevel: .debug,
                                      fileURL: logFileURL2,
                                      filePermission: "600")  // Default permission is "640".
        {
            udpLogger.add(file2)
        }

        if let file3 = try? FileLogger("PersonaPacketLogger",
                                       logLevel: .debug,
                                       fileURL: logFileURL3,
                                       filePermission: "600")  // Default permission is "640".
        {
            udpLogger.add(file3)
        }

        if let file4 = try? FileLogger("PersonaClientWriteLogger",
                                       logLevel: .debug,
                                       fileURL: logFileURL4,
                                       filePermission: "600")  // Default permission is "640".
        {
            udpLogger.add(file4)
        }

        tcpLogger.debug("PersonaTCPLogger Start")
        udpLogger.debug("PersonaUDPLogger Start")
        packetLogger.debug("PersonaPacketLogger Start")
        clientWriteLog.info("PersonaClientWriteLogger Start")

        self.connection = AsyncSystemdConnection(logger)

        self.udpProxy = UdpProxy(client: self.connection, logger: logger, udpLogger: udpLogger, writeLogger: clientWriteLog)
        self.tcpProxy = TcpProxy(client: self.connection, quietTime: false, logger: logger, tcpLogger: tcpLogger)
    }

    public func run() async throws
    {
        while true
        {
            do
            {
                let message = try await self.connection.readWithLengthPrefix(prefixSizeInBits: 32)
                self.logger.info("Persona.run read a message of size \(message.count)")
                try await self.handleMessage(message)
            }
            catch
            {
                self.logger.error("Persona.run: \(error) | \(error.localizedDescription)")
                return
            }
        }
    }

    func handleMessage(_ data: Data) async throws
    {
        let packet = Packet(ipv4Bytes: data, timestamp: Date(), debugPrints: true)

        if let ipv4 = packet.ipv4, let tcp = packet.tcp
        {
            self.logger.debug("TCP packet \(tcp.destinationPort)")

            if let payload = tcp.payload
            {
                self.packetLogger.info("TCP: \(ipv4.sourceAddress):\(tcp.sourcePort) -> \(ipv4.destinationAddress):\(tcp.destinationPort) - \(payload.count) byte payload")
            }
            else
            {
                self.packetLogger.info("TCP: \(ipv4.sourceAddress):\(tcp.sourcePort) -> \(ipv4.destinationAddress):\(tcp.destinationPort) - no payload")
            }

            try await self.tcpProxy.processUpstreamPacket(packet)
        }
        else if let ipv4 = packet.ipv4, let udp = packet.udp
        {
            self.logger.debug("UDP packet")

            if let payload = udp.payload
            {
                self.logger.debug("UDP packet WITH PAYLOAD")
                self.packetLogger.info("UDP: \(ipv4.sourceAddress):\(udp.sourcePort) -> \(ipv4.destinationAddress):\(udp.destinationPort) - \(payload.count) byte payload")

                try await self.udpProxy.processLocalPacket(packet)
            }
            else
            {
                self.packetLogger.info("UDP: \(ipv4.sourceAddress):\(udp.sourcePort) -> \(ipv4.destinationAddress):\(udp.destinationPort) - no payload")

                throw PersonaError.emptyPayload
            }
        }
        else if let ipv4 = packet.ipv4
        {
            if let payload = ipv4.payload
            {
                self.packetLogger.info("\(ipv4.sourceAddress) -> \(ipv4.destinationAddress) - \(payload.count) byte payload")
            }
            else
            {
                self.packetLogger.info("\(ipv4.sourceAddress) -> \(ipv4.destinationAddress) - no payload")
            }
        }
        else
        {
            self.packetLogger.info("Non-IPv4 packet - \(data.hex)")
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
