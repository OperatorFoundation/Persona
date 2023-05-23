//
//  Persona.swift
//  
//
//  Created by Dr. Brandon Wiley on 2/24/22.
//
#if os(macOS) || os(iOS)
import os.log
#endif

import Foundation
import Logging

import Chord
import Flower
import Gardener
import InternetProtocols
import KeychainCli
import Net
import Puppy
import Spacetime
import SwiftHexTools
import Transmission
import TransmissionTypes
import Universe

public class Persona: Universe
{
    var tcpLogger = Puppy()
    
    let connectionsQueue = DispatchQueue(label: "ConnectionsQueue")
    let echoUdpQueue = DispatchQueue(label: "EchoUdpQueue")
    let echoTcpQueue = DispatchQueue(label: "EchoTcpQueue")
    let echoTcpConnectionQueue = DispatchQueue(label: "EchoTcpConnectionQueue")

    var pool = AddressPool()
    var conduitCollection = ConduitCollection()
    
    let listenAddr: String
    let listenPort: Int
    var echoPort = 2233

    var mode: ServerMode! = nil
    var udpProxy: UdpProxy! = nil
    var tcpProxy: TcpProxy! = nil
    var recordID: UInt64 = 0

    public init(listenAddr: String, listenPort: Int, effects: BlockingQueue<Effect>, events: BlockingQueue<Event>, mode: ServerMode)
    {
        self.listenAddr = listenAddr
        self.listenPort = listenPort
        
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
    
        super.init(effects: effects, events: events, logger: logger)

        self.mode = mode
        self.udpProxy = UdpProxy(universe: self)
        self.tcpProxy = TcpProxy(universe: self, quietTime: false, tcpLogger: tcpLogger)
    }

    public override func main() throws
    {
        if self.mode == .record
        {
            self.clearRecordings()
        }

        let echoUdpListener = try self.listen(listenAddr, echoPort, type: .udp)

        #if os(macOS) || os(iOS)
        Task
        {
            do
            {
                try self.handleUdpEchoListener(echoListener: echoUdpListener)
            }
            catch
            {
                print("* UDP echo listener failed")
            }
        }
        #else
        // MARK: async cannot be replaced with Task because it is not currently supported on Linux
        echoUdpQueue.async
        {
            do
            {
                try self.handleUdpEchoListener(echoListener: echoUdpListener)
            }
            catch
            {
                print("* UDP echo listener failed")
            }
        }
        #endif

        let echoTcpListener = try self.listen(listenAddr, echoPort + 1, type: .tcp)

        #if os(macOS) || os(iOS)
        Task
        {
            do
            {
                try self.handleTcpEchoListener(echoListener: echoTcpListener)
            }
            catch
            {
                print("* TCP echo listener failed")
            }
        }
        #else
        echoTcpQueue.async
        {
            do
            {
                try self.handleTcpEchoListener(echoListener: echoTcpListener)
            }
            catch
            {
                print("* TCP echo listener failed")
            }
        }
        #endif

        let listener = try self.listen(listenAddr, listenPort)
        display("listening on \(listenAddr) \(listenPort)")

        while true
        {
            display("* Waiting to accept a connection.")

            let connection = try listener.accept()

            display("* New connection")
            
            #if os(macOS) || os(iOS)
            Task
            {
                self.handleIncomingConnection(connection)
            }
            #else
            connectionsQueue.async
            {
                self.handleIncomingConnection(connection)
            }
            #endif
        }
    }
    
    func handleUdpEchoListener(echoListener: TransmissionTypes.Listener) throws
    {
        while true
        {
            let connection = try echoListener.accept()
            
            // We are expecting to receive a specific message from MoonbounceAndroid: ᓚᘏᗢ Catbus is UDP tops! ᓚᘏᗢ
            guard let received = connection.read(size: 39) else
            {
                print("* UDP Echo server failed to read 39 bytes, continuing with this connection")
                continue
            }
            
            #if os(Linux)
            if let transmissionConnection = connection as? TransmissionConnection
            {
                
                if let sourceAddress = transmissionConnection.udpOutgoingAddress
                {
                    print("* The source address for this udp packet is: \(sourceAddress)")
                }
                
            }
            #endif
            
            print("* UDP Echo received a message: \(received.string)")
            
            guard connection.write(string: received.string) else
            {
                print("* UDP Echo server failed to write a response, continuing with this connection.")
                continue
            }
            
            print("* UDP Echo server sent a response: \(received.string)")
        }
    }

    func handleTcpEchoListener(echoListener: TransmissionTypes.Listener) throws
    {
        while true
        {
            let connection = try echoListener.accept()
            print("👯 New TCP echo connection")

            Task
            {
                self.handleTcpEchoConnection(connection: connection)
            }
        }
    }

    func handleTcpEchoConnection(connection: TransmissionTypes.Connection)
    {
        print("👯 handleTcpEchoConnection called")
        
        // TODO: Add a loop
        
        guard let received = connection.read(maxSize: 100) else
        {
            print("❌ TCP Echo server failed to read bytes, continuing with this connection, closing")
            connection.close()
            return
        }
        
        guard received.count > 0 else
        {
            print("❌ TCP Echo server read 0 bytes, continuing with this connection, closing")
            connection.close()
            return
        }

        print("🐈 TCP Echo received a message: \(received) - \(received.hex)")

        guard connection.write(data: received) else
        {
            print("❌ TCP Echo server failed to write a response, continuing with this connection, closing")
            connection.close()
            return
        }
       
        print("🐈 TCP Echo server sent a response of \(received): \(received.string)")
    }
    
    // takes a transmission connection and wraps as a flower connection
    func handleIncomingConnection(_ connection: TransmissionTypes.Connection)
    {
        let flowerConnection = FlowerConnection(connection: connection, log: nil, logReads: true, logWrites: true)
        let address: IPv4Address
        
        do
        {
            address = try self.handleFirstMessageOfConnection(flowerConnection)
        }
        catch
        {
            flowerConnection.connection.close()
            return
        }

        while true
        {
            do
            {
                try self.handleNextMessage(address, flowerConnection)
            }
            catch
            {
                continue
            }
        }
    }

    // deals with IP assignment
    func handleFirstMessageOfConnection(_ flowerConnection: FlowerConnection) throws -> IPv4Address
    {
        let message: Message
        if self.mode == .live || self.mode == .record
        {
            guard let m = flowerConnection.readMessage() else
            {
                print("* Persona.handleFirstMessage: failed to read a flower message. Connection closed")
                throw PersonaError.connectionClosed
            }
            message = m
        }
        else // self.mode == .playback
        {
            do
            {
                message = try self.getNextPlaybackMessage()
            }
            catch
            {
                print("* Connection closed")
                throw PersonaError.connectionClosed
            }
        }

        switch message
        {
            case .IPRequestV4:
                guard let address = pool.allocate() else
                {
                    // FIXME - close connection
                    print("* Address allocation failure")
                    throw PersonaError.addressPoolAllocationFailed
                }

                guard let ipv4 = IPv4Address(address) else
                {
                    // FIXME - address could not be parsed as an IPv4 address
                    throw PersonaError.addressStringIsNotIPv4(address)
                }

                conduitCollection.addConduit(address: address, flowerConnection: flowerConnection)

                flowerConnection.writeMessage(message: .IPAssignV4(ipv4))

                return IPv4Address(address)!
            case .IPRequestV6:
                // FIXME - support IPv6
                throw PersonaError.unsupportedFirstMessage(message)
            case .IPRequestDualStack:
                // FIXME - support IPv6
                throw PersonaError.unsupportedFirstMessage(message)
            case .IPReuseV4(let ipv4):
                flowerConnection.writeMessage(message: .IPAssignV4(ipv4))
                throw PersonaError.unsupportedFirstMessage(message)
            case .IPReuseV6(_):
                // FIXME - support IPv6
                throw PersonaError.unsupportedFirstMessage(message)
            case .IPReuseDualStack(_, _):
                // FIXME - support IPv6
                throw PersonaError.unsupportedFirstMessage(message)
            default:
                // FIXME - close connection
                print("* Bad first message: \(message.description)")
                throw PersonaError.unsupportedFirstMessage(message)
        }
    }

    // processes raw packets from the Network Extension or raw packets
    // uses IP library to parse to use the right proxy
    // FIXME: currently only UDP has been implemented
    // after parsing and identifying, pass on to handleParsedMessage()
    func handleNextMessage(_ address: IPv4Address, _ flowerConnection: FlowerConnection) throws
    {
        guard let message = flowerConnection.readMessage() else
        {
            print("\n* Persona.handleNextMessage Failed to read a flower message. The connection is probably closed.")

            if let logs = flowerConnection.readLog
            {
                print("* Persona Readlogs:")
                print("******************")
                for log in logs
                {
                    print(log.hex)
                }
                print("******************")
            }

            throw PersonaError.connectionClosed
        }

        switch message
        {
            case .IPDataV4(let data):
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
                    let streamID = generateStreamID(source: sourceEndpoint, destination: destinationEndpoint)
                                        
                    if tcp.syn // If the syn flag is set, we will ignore all other flags (including acks) and treat this as a syn packet
                    {
                        let parsedMessage: Message = .TCPOpenV4(destinationEndpoint, streamID)
                        try self.handleParsedMessage(address, parsedMessage, packet)
                    }
                    else if tcp.rst // TODO: Flower should be informed if a close message is an rst or a fin
                    {
                        let parsedMessage: Message = .TCPClose(streamID)
                        try self.handleParsedMessage(address, parsedMessage, packet)
                    }
                    else if tcp.fin // TODO: Flower should be informed if a close message is an rst or a fin
                    {
                        let parsedMessage: Message = .TCPClose(streamID)
                        try self.handleParsedMessage(address, parsedMessage, packet)
                    }
                    else
                    {
                        // TODO: Handle the situation where we never see an ack response to our syn/ack (resend the syn/ack)
                        if let payload = tcp.payload
                        {
                            let parsedMessage: Message = .TCPData(streamID, payload)
                            try self.handleParsedMessage(address, parsedMessage, packet)
                        }
                        else if tcp.ack
                        {
                            let parsedMessage: Message = .TCPData(streamID, Data())
                            try self.handleParsedMessage(address, parsedMessage, packet)
                        }
                    }
                }
                else if let udp = packet.udp
                {
                    guard let ipv4Destination = IPv4Address(data: ipv4Packet.destinationAddress) else
                    {
                        // Drop this packet, but then continue processing more packets
                        throw PersonaError.addressDataIsNotIPv4(ipv4Packet.destinationAddress)
                    }

                    let port = NWEndpoint.Port(integerLiteral: udp.destinationPort)
                    let endpoint = EndpointV4(host: ipv4Destination, port: port)
                    guard let payload = udp.payload else
                    {
                        throw PersonaError.emptyPayload
                    }

                    let parsedMessage: Message = .UDPDataV4(endpoint, payload)
                    try self.handleParsedMessage(address, parsedMessage, packet)
                }

            default:
                // Drop this message, but then continue processing more messages
                throw PersonaError.unsupportedNextMessage(message)
        }
    }

    // handles the specifics of the packet types
    // connects to the address that the packet tries connecting to
    // wraps into a new packet with same destination and data and server's source address
    func handleParsedMessage(_ address: IPv4Address, _ message: Message, _ packet: Packet) throws
    {
        switch message
        {
            case .UDPDataV4(_, _):
                print("* Persona received a UPDataV4 type message")
                guard let conduit = self.conduitCollection.getConduit(with: address.string) else
                {
                    print("* Unknown conduit address \(address)")
                    return
                }

                try self.udpProxy.processLocalPacket(conduit, packet)
//                let addressData = endpoint.host.rawValue
//                let addressString = "\(addressData[0]).\(addressData[1]).\(addressData[2]).\(addressData[3])"
//                let port = Int(endpoint.port.rawValue)
//                let connection = try self.connect(addressString, port, ConnectionType.udp)
//                let success = connection.write(data: data)
//                if !success
//                {
//                    print("Failed write")
//                }

            case .UDPDataV6(_, _):
                print("* Persona received a UDPDataV6 type message. This is not currently supported.")
                throw PersonaError.unsupportedParsedMessage(message)
                
            case .TCPOpenV4(_, _), .TCPData(_, _), .TCPClose(_):
                print("* Persona received a TCP message: \(message)")
                guard let conduit = self.conduitCollection.getConduit(with: address.string) else
                {
                    print("* Unknown conduit address \(address)")
                    return
                }

                AsyncAwaitThrowingEffectSynchronizer.sync
                {
                    try await self.tcpProxy.processUpstreamPacket(conduit, packet)
                }
                
            default:
                throw PersonaError.unsupportedParsedMessage(message)
        }
    }

    public func clearRecordings()
    {
        var messageID: UInt64 = 0
        while true
        {
            do
            {
                try self.delete(identifier: messageID)
                messageID = messageID + 1
            }
            catch
            {
                return
            }
        }
    }

    func getNextPlaybackMessage() throws -> Message
    {
        let message: Message = try self.load(identifier: self.recordID)
        self.recordID = self.recordID + 1

        return message
    }

    public func shutdown()
    {
        if File.exists("dataDatabase")
        {
            if let contents = File.contentsOfDirectory(atPath: "dataDatabase")
            {
                if contents.isEmpty
                {
                    let _ = File.delete(atPath: "dataDatabase")
                }
            }
        }

        if File.exists("relationDatabase")
        {
            if let contents = File.contentsOfDirectory(atPath: "relationDatabase")
            {
                if contents.isEmpty
                {
                    let _ = File.delete(atPath: "relationDatabase")
                }
            }
        }
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

        if let test = TransmissionConnection(host: address, port: port)
        {
            test.close()

            throw NewCommandError.portInUse(port)
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
    case unsupportedFirstMessage(Message)
    case unsupportedNextMessage(Message)
    case unsupportedParsedMessage(Message)
    case connectionClosed
    case packetNotIPv4(Data)
    case unsupportedPacketType(Data)
    case emptyPayload
    case echoListenerFailure
}
