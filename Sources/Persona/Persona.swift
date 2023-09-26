//
//  Persona.swift
//
//
//  Created by Dr. Brandon Wiley on 2/24/22.
//
import FileLogging
import Logging
import Foundation

import Chord
import Gardener
import InternetProtocols
import Puppy
import Net
import TransmissionAsync

public enum Subsystem: UInt8
{
    case Client   = 1
    case Udpproxy = 2
    case Tcpproxy = 3
}

public class Persona
{
    public let stats: Stats = Stats()

    let connection: AsyncConnection
    let logger: Logger

    var tcpLogger = Puppy()
    var udpLogger = Puppy()
    var packetLogger = Puppy()
    var clientWriteLog = Puppy()

    var udpProxy: UdpProxy! = nil
    var tcpProxy: TcpProxy! = nil

    public init() async throws
    {
        // First we set up the logging. There are several loggers that log different specific events that are helpful for debugging.
        // The location of the log files assumes that you have Persona checked out in the home directory of the root user.
        let mainLogURL = URL(fileURLWithPath: "/root/Persona/Persona.log")
        var logger = try FileLogging.logger(label: "Persona", localFile: mainLogURL)
        logger.logLevel = .info
        self.logger = logger

        let logFileURL = File.homeDirectory().appendingPathComponent("Persona/PersonaTcpLog.log", isDirectory: false)
        let logFileURL2 = File.homeDirectory().appendingPathComponent("Persona/PersonaUdpLog.log", isDirectory: false)
        let logFileURL3 = File.homeDirectory().appendingPathComponent("Persona/PersonaPacketLog.log", isDirectory: false)
        let logFileURL4 = File.homeDirectory().appendingPathComponent("Persona/PersonaClientWriteLog.log", isDirectory: false)

        if File.exists(logFileURL.path)
        {
            let _ = File.delete(atPath: logFileURL.path)
        }

        if File.exists(logFileURL2.path)
        {
            let _ = File.delete(atPath: logFileURL2.path)
        }

        if File.exists(logFileURL3.path)
        {
            let _ = File.delete(atPath: logFileURL3.path)
        }

        if File.exists(logFileURL4.path)
        {
            let _ = File.delete(atPath: logFileURL4.path)
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
            clientWriteLog.add(file4)
        }

        let now = Date()
        self.logger.info("🏀 Persona Start \(now) 🏀") // General log for debugging with probably too much information to follow
        self.packetLogger.info("🏀 PersonaPacketLogger Start \(now)🏀") // Logs of only events related to packets
        self.tcpLogger.info("🏀 PersonaTCPLogger Start \(now)🏀") // Log of only events related to TCP packets that are part of the client TCP test
        self.udpLogger.info("🏀 PersonaUDPLogger Start \(now)🏀") // Log of only events related to UDP packets that are part of the client UDP test
        self.clientWriteLog.info("🏀 PersonaClientWriteLogger Start \(now)🏀") // Log of only writes to the client

        // Connect to systemd input and output streams
        // Persona only runs under systemd. You cannot run it directly on the command line.
        self.connection = AsyncSystemdConnection(logger)

        // Run Persona's UDP proxying control logic
        self.udpProxy = try await UdpProxy(client: self.connection, logger: logger, udpLogger: udpLogger, writeLogger: clientWriteLog)

        // Run Persona's TCP proxying control logic
        self.tcpProxy = TcpProxy(client: self.connection, logger: self.logger, tcpLogger: self.tcpLogger, writeLogger: self.clientWriteLog)
    }

    // Start the Persona processing loop. Please note that each client gets its own Persona instance.
    public func run() async throws
    {
        while true
        {
            self.logger.info("Persona.run - main loop")

            self.logger.info("Persona.run - reading message from client, blocking")
            do
            {
                let message = try await self.connection.readWithLengthPrefix(prefixSizeInBits: 32)

                do
                {
                    // Process the packet that we received from the downstream client
                    self.logger.info("Persona.run - handling message")
                    try await self.handleMessage(message)
                    self.logger.info("Persona.run - done")
                }
                catch
                {
                    self.logger.error("Persona.run - failed to handle message: \(message): \(error). Moving on to next message.")
                }
            }
            catch
            {
                self.logger.error("Persona.run: reading from client failed: \(error) | \(error.localizedDescription)")
                self.logger.error("Persona.run: assuming client connection closed, exiting Persona.")

                await self.close()
            }
        }
    }

    func close() async
    {
        for tcpConnection in TcpProxyConnection.getConnections()
        {
            try? await tcpConnection.close()
        }

        exit(0)
    }

    func handleMessage(_ data: Data) async throws
    {
        self.logger.info("Persona.handleMessage(\(data.count) bytes)")

        guard data.count > 0 else
        {
            self.logger.error("Persona.handleMessage - no data")
            throw PersonaError.noData
        }

        let subsystemByte = data[0]
        let rest = Data(data[1...])

        guard let subsystem = Subsystem(rawValue: subsystemByte) else
        {
            self.logger.error("Persona.handleMessage - unknown subsystem \(subsystemByte)")
            throw PersonaError.unknownSubsystem(subsystemByte)
        }

        switch subsystem
        {
            case .Client:
                self.logger.info("Persona.handleMessage - client message")
                try await self.handleClientMessage(rest)

            case .Tcpproxy:
                self.logger.info("Persona.handleMessage - tcpproxy message")
                try await self.handleTcpproxyMessage(rest)

            case .Udpproxy:
                self.logger.info("Persona.handleMessage - udpproxy message")
                try await self.handleUdpproxyMessage(rest)
        }
    }

    public func handleClientMessage(_ data: Data) async throws
    {
        self.logger.info("Persona.handleClientMessage(\(data.count) bytes)")
        // Attempt to parse the data we received from the downstream client as an IPv4 packet.
        // Note that we only support IPv4 packets and we only support TCP and UDP packets.
        let packet = Packet(ipv4Bytes: data, timestamp: Date())

        if let ipv4 = packet.ipv4, let tcp = packet.tcp
        {
            // The packet is IPv4/TCP.

            self.stats.ipv4 += 1
            self.stats.tcp += 1

            self.logger.debug("🪀 -> TCP: \(description(ipv4, tcp))")

            if tcp.destinationPort == 7
            {
                self.tcpLogger.debug("🪀 -> TCP: \(description(ipv4, tcp))")
            }

            self.packetLogger.debug("🪀 -> TCP: \(description(ipv4, tcp))")

             // Process TCP packets
            try await self.tcpProxy.processDownstreamPacket(ipv4: ipv4, tcp: tcp, payload: tcp.payload)
        }
        else if let ipv4 = packet.ipv4, let udp = packet.udp
        {
            // The packet is IPv4/UDP.

            self.stats.ipv4 += 1
            self.stats.udp += 1

            if let payload = udp.payload
            {
                self.logger.debug("🏓 UDP: \(ipv4.sourceAddress.ipv4AddressString ?? "not an ipv4 address"):\(udp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "not an ipv4 address"):\(udp.destinationPort) - \(payload.count) byte payload")
                self.packetLogger.debug("🏓 UDP: \(ipv4.sourceAddress.ipv4AddressString ?? "not an ipv4 address"):\(udp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "not an ipv4 address"):\(udp.destinationPort) - \(payload.count) byte payload")

                // Process only UDP packets with payloads
                try await self.udpProxy.processDownstreamPacket(ipv4: ipv4, udp: udp, payload: payload)
            }
            else
            {
                self.logger.debug("🏓 UDP: \(ipv4.sourceAddress.ipv4AddressString ?? "not an ipv4 address"):\(udp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "not an ipv4 address"):\(udp.destinationPort) - no payload")
                self.packetLogger.debug("🏓 UDP: \(ipv4.sourceAddress.ipv4AddressString ?? "not an ipv4 address"):\(udp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "not an ipv4 address"):\(udp.destinationPort) - no payload")

                // Reject UDP packets without payloads
                throw PersonaError.emptyPayload
            }
        }
        else if let _ = packet.ipv4
        {
            // The packet is IPv4, but neither TCP nor UDP.

//            self.logger.info("IPv4 packet, neither TCP nor UDP: \(ipv4.protocolNumber)")
//            self.packetLogger.info("IPv4 packet, neither TCP nor UDP: \(ipv4.protocolNumber)")

            // IPv4 packets that are neither TCP nor UDP are not supported

            self.stats.ipv4 += 1
            self.stats.nonTcpUdpIPv4 += 1
        }
        else
        {
            // The packet is not IPv4.

            self.stats.nonIPv4 += 1

//            self.logger.info("Non-IPv4 packet - \(data.hex)")
//            self.packetLogger.info("Non-IPv4 packet - \(data.hex)")

            // Non-IPv4 packets are not supported
        }
    }

    public func handleTcpproxyMessage(_ data: Data) async throws
    {
        self.logger.info("Persona.handleTcpproxyMessage(\(data.count) bytes)")
        try await self.tcpProxy.handleMessage(data)
    }

    public func handleUdpproxyMessage(_ data: Data) async throws
    {
        self.logger.info("Persona.handleUdpproxyMessage(\(data.count) bytes)")
        try await self.udpProxy.handleMessage(data)
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
    case noData
    case unknownSubsystem(UInt8)
}
