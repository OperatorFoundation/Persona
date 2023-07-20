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
    var pool = AddressPool()
    var conduitCollection = ConduitCollection()

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
                let message = try await self.connection.readWithLengthPrefix(prefixSizeInBits: 64)
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
        guard let ipv4Packet = packet.ipv4 else
        {
            // Drop this packet, but then continue processing more packets
            print("* Persona.handleNextMessage: received data was not an IPV4 packet, ignoring this packet.")
            throw PersonaError.packetNotIPv4(data)
        }

        if let tcp = packet.tcp
        {
            guard let ipv4Source = IPv4Address(data: ipv4Packet.sourceAddress) else
            {
                // Drop this packet, but then continue processing more packets
                throw PersonaError.addressDataIsNotIPv4(ipv4Packet.destinationAddress)
            }

            let sourcePort = NWEndpoint.Port(integerLiteral: tcp.sourcePort)
            let sourceEndpoint = EndpointV4(host: ipv4Source, port: sourcePort)

            guard let ipv4Destination = IPv4Address(data: ipv4Packet.destinationAddress) else
            {
                // Drop this packet, but then continue processing more packets
                throw PersonaError.addressDataIsNotIPv4(ipv4Packet.destinationAddress)
            }
            let destinationPort = NWEndpoint.Port(integerLiteral: tcp.destinationPort)
            let destinationEndpoint = EndpointV4(host: ipv4Destination, port: destinationPort)

            try await self.tcpProxy.processUpstreamPacket(packet)
        }
        else if let udp = packet.udp
        {
            guard let ipv4Destination = IPv4Address(data: ipv4Packet.destinationAddress) else
            {
                // Drop this packet, but then continue processing more packets
                throw PersonaError.addressDataIsNotIPv4(ipv4Packet.destinationAddress)
            }

            let port = NWEndpoint.Port(integerLiteral: udp.destinationPort)
            guard udp.payload != nil else
            {
                throw PersonaError.emptyPayload
            }

            try self.udpProxy.processLocalPacket(packet)
        }
    }

    public func shutdown()
    {
    }

    /// Creates a new `KeyType.P256KeyAgreement` key and saves it to the system keychain,
    /// generates a server config and a client config, and saves the config pair as JSON files to the provided file URLs
    ///
    /// - parameter name: A `String` that will be used to name the server, this will also be used to name the config files.
    /// - parameter port: The port that the server will listen on as an `Int`.
    /// - parameter serverConfigURL: The file `URL` where the server config file should be saved.
    /// - parameter clientConfigURL: The file `URL` where the client config file should be saved.
    /// - parameter keychainURL: The directory `URL` where the keychain should be created.
    /// - parameter keychainLabel: A `String` that will be used to name the new keys.
    static public func generateNew(name: String, ip: String?, port: Int, serverConfigURL: URL, clientConfigURL: URL, keychainURL: URL, keychainLabel: String) throws
    {
        let address: String
        if let ip = ip
        {
            address = ip
        }
        else
        {
            address = try Ipify.getPublicIP()
        }

        guard let keychain = Keychain(baseDirectory: keychainURL) else
        {
            throw NewCommandError.couldNotLoadKeychain
        }

        guard let privateKeyKeyAgreement = keychain.generateAndSavePrivateKey(label: keychainLabel, type: KeyType.P256KeyAgreement) else
        {
            throw NewCommandError.couldNotGeneratePrivateKey
        }

        let serverConfig = ServerConfig(name: name, host: address, port: port)
        try serverConfig.save(to: serverConfigURL)
        print("Wrote config to \(serverConfigURL.path)")

        let publicKeyKeyAgreement = privateKeyKeyAgreement.publicKey
        let clientConfig = ClientConfig(name: name, host: address, port: port, serverPublicKey: publicKeyKeyAgreement)
        try clientConfig.save(to: clientConfigURL)
        print("Wrote config to \(clientConfigURL.path)")
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
