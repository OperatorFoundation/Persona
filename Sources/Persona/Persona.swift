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
    public let stats: Stats

    let connection: AsyncConnection
    let logger: Logger

    var tcpLogger = Puppy()
    var udpLogger = Puppy()
    var packetLogger = Puppy()
    var clientWriteLog = Puppy()
    var statusLog = Puppy()

    var udpProxy: UdpProxy! = nil
    var tcpProxy: TcpProxy! = nil

    public init(socket: Bool) async throws
    {
        print("Persona.init(\(socket))")
        // First we set up the logging. There are several loggers that log different specific events that are helpful for debugging.
        // The location of the log files assumes that you have Persona checked out in the home directory of the root user.
        let mainLogURL = File.homeDirectory().appendingPathComponent("Persona/Persona.log", isDirectory: false)
        var logger = try FileLogging.logger(label: "Persona", localFile: mainLogURL)
        logger.logLevel = .info
        self.logger = logger

        let logFileURL = File.homeDirectory().appendingPathComponent("Persona/PersonaTcpLog.log", isDirectory: false)
        let logFileURL2 = File.homeDirectory().appendingPathComponent("Persona/PersonaUdpLog.log", isDirectory: false)
        let logFileURL3 = File.homeDirectory().appendingPathComponent("Persona/PersonaPacketLog.log", isDirectory: false)
        let logFileURL4 = File.homeDirectory().appendingPathComponent("Persona/PersonaClientWriteLog.log", isDirectory: false)
        let statusFileURL = File.homeDirectory().appendingPathComponent("Persona/PersonaStats.log", isDirectory: false)

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

        if File.exists(statusFileURL.path)
        {
            let _ = File.delete(atPath: statusFileURL.path)
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

        if let statusFile = try? FileLogger("PersonaStatusLogger",
                                       logLevel: .debug,
                                       fileURL: statusFileURL,
                                       filePermission: "600")  // Default permission is "640".
        {
            statusLog.add(statusFile)
        }

        let now = Date()
        self.logger.info("🏀 Persona Start \(now) 🏀") // General log for debugging with probably too much information to follow
        self.packetLogger.info("🏀 PersonaPacketLogger Start \(now)🏀") // Logs of only events related to packets
        self.tcpLogger.info("🏀 PersonaTCPLogger Start \(now)🏀") // Log of only events related to TCP packets that are part of the client TCP test
        self.udpLogger.info("🏀 PersonaUDPLogger Start \(now)🏀") // Log of only events related to UDP packets that are part of the client UDP test
        self.clientWriteLog.info("🏀 PersonaClientWriteLogger Start \(now)🏀") // Log of only writes to the client

        self.stats = Stats(logger: statusLog)

        // Connect to systemd input and output streams
        // Persona only runs under systemd. You cannot run it directly on the command line.
        if socket
        {
            print("listening 127.0.0.1:1230")
            let listener = try AsyncTcpSocketListener(port: 1230, self.logger)

            print("accepting connection...")
            self.connection = try await listener.accept()

            print("connection accepted!")
        }
        else
        {
            self.connection = AsyncStdioConnection(logger)
        }

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
            do
            {
                let message = try await self.connection.readWithLengthPrefix(prefixSizeInBits: 32)

                do
                {
                    // Process the packet that we received from the downstream client
                    try await self.handleMessage(message)
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
        self.stats.messages = self.stats.messages + 1
        if self.stats.messages % 10000 == 0 // Every 10000 messages, write stats log
        {
            self.logger.info("writing stats log, packet #\(self.stats.messages)")
            self.stats.writeLog()
        }

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
                try await self.handleClientMessage(rest)

            case .Tcpproxy:
                try await self.handleTcpproxyMessage(rest)

            case .Udpproxy:
                try await self.handleUdpproxyMessage(rest)
        }
    }

    public func handleClientMessage(_ data: Data) async throws
    {
        // Attempt to parse the data we received from the downstream client as an IPv4 packet.
        // Note that we only support IPv4 packets and we only support TCP and UDP packets.
        let packet = Packet(ipv4Bytes: data, timestamp: Date())

        if let ipv4 = packet.ipv4, let tcp = packet.tcp
        {
            // The packet is IPv4/TCP.

            self.stats.ipv4 += 1
            self.stats.tcp += 1

            #if DEBUG
            self.logger.debug("🪀 -> TCP: \(description(ipv4, tcp))")
            #endif

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
                #if DEBUG
                self.logger.debug("🏓 UDP: \(ipv4.sourceAddress.ipv4AddressString ?? "not an ipv4 address"):\(udp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "not an ipv4 address"):\(udp.destinationPort) - \(payload.count) byte payload")
                #endif

                // Process only UDP packets with payloads
                try await self.udpProxy.processDownstreamPacket(ipv4: ipv4, udp: udp, payload: payload)
            }
            else
            {
                #if DEBUG
                self.logger.debug("🏓 UDP: \(ipv4.sourceAddress.ipv4AddressString ?? "not an ipv4 address"):\(udp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "not an ipv4 address"):\(udp.destinationPort) - no payload")
                #endif

                // Reject UDP packets without payloads
                throw PersonaError.emptyPayload
            }
        }
        else if let _ = packet.ipv4
        {
            // The packet is IPv4, but neither TCP nor UDP.
            // IPv4 packets that are neither TCP nor UDP are not supported

            self.stats.ipv4 += 1
            self.stats.nonTcpUdpIPv4 += 1
        }
        else
        {
            // The packet is not IPv4.
            // Non-IPv4 packets are not supported

            self.stats.nonIPv4 += 1
        }
    }

    public func handleTcpproxyMessage(_ data: Data) async throws
    {
        try await self.tcpProxy.handleMessage(data)
    }

    public func handleUdpproxyMessage(_ data: Data) async throws
    {
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
