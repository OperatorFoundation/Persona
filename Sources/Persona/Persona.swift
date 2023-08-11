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

    public init() async throws
    {
        // First we set up the logging. There are several loggers that log different specific events that are helpful for debugging.
        // The location of the log files assumes that you have Persona checked out in the home directory of the root user.
        let mainLogURL = URL(fileURLWithPath: "/root/Persona/Persona.log")
        self.logger = try FileLogging.logger(label: "Persona", localFile: mainLogURL)

        let logFileURL = File.homeDirectory().appendingPathComponent("Persona/PersonaTcpLog.log", isDirectory: false)
        let logFileURL2 = File.homeDirectory().appendingPathComponent("Persona/PersonaUdpLog.log", isDirectory: false)
        let logFileURL3 = File.homeDirectory().appendingPathComponent("Persona/PersonaPacketLog.log", isDirectory: false)
        let logFileURL4 = File.homeDirectory().appendingPathComponent("Persona/PersonaClientWriteLog.log", isDirectory: false)

//        if File.exists(logFileURL.path)
//        {
//            let _ = File.delete(atPath: logFileURL.path)
//        }
//
//        if File.exists(logFileURL2.path)
//        {
//            let _ = File.delete(atPath: logFileURL2.path)
//        }
//
//        if File.exists(logFileURL3.path)
//        {
//            let _ = File.delete(atPath: logFileURL3.path)
//        }
//
//        if File.exists(logFileURL4.path)
//        {
//            let _ = File.delete(atPath: logFileURL4.path)
//        }

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
        self.packetLogger.debug("🏀 PersonaPacketLogger Start \(now)🏀") // Logs of only events related to packets
        self.tcpLogger.debug("🏀 PersonaTCPLogger Start \(now)🏀") // Log of only events related to TCP packets that are part of the client TCP test
        self.udpLogger.debug("🏀 PersonaUDPLogger Start \(now)🏀") // Log of only events related to UDP packets that are part of the client UDP test
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
            do
            {
                // Persona expects the client to send raw IPv4 packets prefixed with a 4-byte length
                // All responses will also be raw IPv4 packets prefixed with a 4-byte length
                self.logger.info("Persona.run - reading from client...")

                let message = try await self.connection.readWithLengthPrefix(prefixSizeInBits: 32)

                self.logger.info("Persona.run - reading from client succeeded - read a message of size \(message.count)")

                // Process the packet that we received from the downstream client
                try await self.handleMessage(message)
            }
            catch
            {
                self.logger.error("Persona.run: reading from client failed: \(error) | \(error.localizedDescription)")
                return
            }
        }
    }

    func handleMessage(_ data: Data) async throws
    {
        // Attempt to parse the data we received from the downstream client as an IPv4 packet.
        // Note that we only support IPv4 packets and we only support TCP and UDP packets.
        let packet = Packet(ipv4Bytes: data, timestamp: Date(), debugPrints: true)

        if let ipv4 = packet.ipv4, let tcp = packet.tcp
        {
            // The packet is IPv4/TCP.

            if let payload = tcp.payload
            {
                self.logger.info("🪀 TCP: \(ipv4.sourceAddress.ipv4AddressString ?? "not an ipv4 address"):\(tcp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "not an ipv4 address"):\(tcp.destinationPort) - \(payload.count) byte payload")
                self.packetLogger.info("🪀 TCP: \(ipv4.sourceAddress.ipv4AddressString ?? "not an ipv4 address"):\(tcp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "not an ipv4 address"):\(tcp.destinationPort) - \(payload.count) byte payload")
            }
            else
            {
                self.logger.info("🪀 TCP: \(ipv4.sourceAddress.ipv4AddressString ?? "not an ipv4 address"):\(tcp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "not an ipv4 address"):\(tcp.destinationPort) - no payload")
                self.packetLogger.info("🪀 TCP: \(ipv4.sourceAddress.ipv4AddressString ?? "not an ipv4 address"):\(tcp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "not an ipv4 address"):\(tcp.destinationPort) - no payload")
            }

            // Process TCP packets
            try await self.tcpProxy.processDownstreamPacket(ipv4: ipv4, tcp: tcp, payload: tcp.payload)
        }
        else if let ipv4 = packet.ipv4, let udp = packet.udp
        {
            // The packet is IPv4/UDP.

            if let payload = udp.payload
            {
                self.logger.info("🏓 UDP: \(ipv4.sourceAddress.ipv4AddressString ?? "not an ipv4 address"):\(udp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "not an ipv4 address"):\(udp.destinationPort) - \(payload.count) byte payload")
                self.packetLogger.info("🏓 UDP: \(ipv4.sourceAddress.ipv4AddressString ?? "not an ipv4 address"):\(udp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "not an ipv4 address"):\(udp.destinationPort) - \(payload.count) byte payload")

                // Process only UDP packets with payloads
                try await self.udpProxy.processDownstreamPacket(ipv4: ipv4, udp: udp, payload: payload)
            }
            else
            {
                self.logger.info("🏓 UDP: \(ipv4.sourceAddress.ipv4AddressString ?? "not an ipv4 address"):\(udp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "not an ipv4 address"):\(udp.destinationPort) - no payload")
                self.packetLogger.info("🏓 UDP: \(ipv4.sourceAddress.ipv4AddressString ?? "not an ipv4 address"):\(udp.sourcePort) -> \(ipv4.destinationAddress.ipv4AddressString ?? "not an ipv4 address"):\(udp.destinationPort) - no payload")

                // Reject UDP packets without payloads
                throw PersonaError.emptyPayload
            }
        }
        else if let ipv4 = packet.ipv4
        {
            // The packet is IPv4, but neither TCP nor UDP.

            self.logger.info("IPv4 packet, neither TCP nor UDP: \(ipv4.protocolNumber)")
            self.packetLogger.info("IPv4 packet, neither TCP nor UDP: \(ipv4.protocolNumber)")

            // IPv4 packets that are neither TCP nor UDP are not supported
        }
        else
        {
            // The packet is not IPv4.

            self.logger.info("Non-IPv4 packet - \(data.hex)")
            self.packetLogger.info("Non-IPv4 packet - \(data.hex)")

            // Non-IPv4 packets are not supported
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
