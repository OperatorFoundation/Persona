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
        
        let logFileURL = URL(fileURLWithPath: "PersonaTcpLog.log")
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

        // MARK: async cannot be replaced with Task because it is not currently supported on Linux
        echoUdpQueue.async
        {
            do
            {
                try self.handleUdpEchoListener(echoListener: echoUdpListener)
            }
            catch
            {
                print("UDP echo listener failed")
            }
        }

        let echoTcpListener = try self.listen(listenAddr, echoPort + 1, type: .tcp)

        echoTcpQueue.async
        {
            do
            {
                try self.handleTcpEchoListener(echoListener: echoTcpListener)
            }
            catch
            {
                print("TCP echo listener failed")
            }
        }

        display("listening on \(listenAddr) \(listenPort)")
        
        let listener = try self.listen(listenAddr, listenPort)

        while true
        {
            display("Waiting to accept a connection.")

            let connection = try listener.accept()

            display("New connection")

            // MARK: async cannot be replaced with Task because it is not currently supported on Linux
            connectionsQueue.async
            {
                self.handleIncomingConnection(connection)
            }
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
                print("UDP Echo server failed to read 39 bytes, continuing with this connection")
                continue
            }
            
            #if os(Linux)
            if let transmissionConnection = connection as? TransmissionConnection
            {
                
                if let sourceAddress = transmissionConnection.udpOutgoingAddress
                {
                    print("The source address for this udp packet is: \(sourceAddress)")
                }
                
            }
            #endif
            
            print("UDP Echo received a message: \(received.string)")
            
            guard connection.write(string: received.string) else
            {
                print("UDP Echo server failed to write a response, continuing with this connection.")
                continue
            }
            
            print("UDP Echo server sent a response: \(received.string)")
        }
    }

    func handleTcpEchoListener(echoListener: TransmissionTypes.Listener) throws
    {
        while true
        {
            let connection = try echoListener.accept()
            print("New TCP echo connection")

            self.echoTcpConnectionQueue.async
            {
                self.handleTcpEchoConnection(connection: connection)
            }
        }
    }

    func handleTcpEchoConnection(connection: TransmissionTypes.Connection)
    {
        guard let received = connection.read(maxSize: 41) else
        {
            print("❌ TCP Echo server failed to read bytes, continuing with this connection, closing")
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
       
        print("🐈 TCP Echo server sent a response: \(received.string)")
    }
    
    // takes a transmission connection and wraps as a flower connection
    func handleIncomingConnection(_ connection: TransmissionTypes.Connection)
    {
        print("Persona.handleIncomingConnection() called.")
        
        // FIXME - add logging
        let flowerConnection = FlowerConnection(connection: connection, log: nil, logReads: true, logWrites: true)
        
        print("Persona created a Flower connection from incoming connection.")

        let address: IPv4Address
        do
        {
            print("Persona.handleIncomingConnection: Calling handleFirstMessage()")
            
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
        print("Persona.handleFirstMessage() called")
        let message: Message
        if self.mode == .live || self.mode == .record
        {
            print("Persona.handleFirstMessage: attempting to read from our flower connection...")
            
            guard let m = flowerConnection.readMessage() else
            {
                print("Persona.handleFirstMessage: failed to read a flower message. Connection closed")
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
                print("Connection closed")
                throw PersonaError.connectionClosed
            }
        }

        print("Persona.handleFirstMessage: received an \(message.description)")

        if self.mode == .record
        {
            self.recordMessage(message)
        }
        
        switch message
        {
            case .IPRequestV4:
                guard let address = pool.allocate() else
                {
                    // FIXME - close connection
                    print("Address allocation failure")
                    throw PersonaError.addressPoolAllocationFailed
                }

                guard let ipv4 = IPv4Address(address) else
                {
                    // FIXME - address could not be parsed as an IPv4 address
                    throw PersonaError.addressStringIsNotIPv4(address)
                }

                conduitCollection.addConduit(address: address, flowerConnection: flowerConnection)

                print("Persona.handleFirstMessage: calling flowerConnection.writeMessage()")
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
                print("Bad first message: \(message.description)")
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
                print("Readlogs:")
                print("******************")
                for log in logs
                {
                    print(log.hex)
                }
                print("******************")
            }

            throw PersonaError.connectionClosed
        }
        
        tcpLogger.debug("\n************************************************************")
        tcpLogger.debug("* Persona.handleNextMessage: received a \(message.description)")
        
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
                
                print("* Persona.handleNextMessage: received an IPV4 packet")

                if let tcp = packet.tcp
                {
                    tcpLogger.debug("*** Parsing a TCP Packet ***")

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
                    
                    if tcp.destinationPort == 2234 {
                        tcpLogger.debug("* source address: \(sourceEndpoint.host.string):\(sourceEndpoint.port.rawValue)")
                        tcpLogger.debug("* destination address: \(destinationEndpoint.host.string):\(destinationEndpoint.port.rawValue)")
                        tcpLogger.debug("* sequence number:")
                        tcpLogger.debug("* \(tcp.sequenceNumber.uint32 ?? 0)")
                        tcpLogger.debug("* \(tcp.sequenceNumber.hex)")
                        tcpLogger.debug("* acknowledgement number:")
                        tcpLogger.debug("* \(tcp.acknowledgementNumber.uint32 ?? 0)")
                        tcpLogger.debug("* \(tcp.acknowledgementNumber.hex)")
                        tcpLogger.debug("* syn: \(tcp.syn)")
                        tcpLogger.debug("* ack: \(tcp.ack)")
                        tcpLogger.debug("* fin: \(tcp.fin)")
                        tcpLogger.debug("* rst: \(tcp.rst)")
                        tcpLogger.debug("* window size: \(tcp.windowSize)")
                        if let options = tcp.options {
                            tcpLogger.debug("* tcp options: \(options.hex)")
                        } else {
                            tcpLogger.debug("* no tcp options")
                        }
                        
                        if let payload = tcp.payload {
                            tcpLogger.debug("* payload: \(payload.count) *")
                        }
                        else {
                            tcpLogger.debug("* no payload *")
                        }
                        
                        tcpLogger.debug("* streamID: \(streamID)")
                        tcpLogger.debug("* IPV4 packet parsed ❣️")
                        tcpLogger.debug("************************************************************\n")
                    }
                    
                    if tcp.syn // If the syn flag is set, we will ignore all other flags (including acks) and treat this as a syn packet
                    {
                        let parsedMessage: Message = .TCPOpenV4(destinationEndpoint, streamID)
                        tcpLogger.debug("* tcp.syn received. Message is TCPOpenV4")
                        try self.handleParsedMessage(address, parsedMessage, packet)
                    }
                    else if tcp.rst // TODO: Flower should be informed if a close message is an rst or a fin
                    {
                        let parsedMessage: Message = .TCPClose(streamID)
                        tcpLogger.debug("* tcp.rst received. Message is TCPClose")
                        try self.handleParsedMessage(address, parsedMessage, packet)
                    }
                    else if tcp.fin // TODO: Flower should be informed if a close message is an rst or a fin
                    {
                        let parsedMessage: Message = .TCPClose(streamID)
                        tcpLogger.debug("* tcp.fin received. Message is TCPClose")
                        try self.handleParsedMessage(address, parsedMessage, packet)
                    }
                    else
                    {
                        // TODO: Handle the situation where we never see an ack response to our syn/ack (resend the syn/ack)
                        if let payload = tcp.payload
                        {
                            let parsedMessage: Message = .TCPData(streamID, payload)
                            tcpLogger.debug("* Received a payload. Parsed the message as TCPData")
                            
                            try self.handleParsedMessage(address, parsedMessage, packet)
                        }
                        else if tcp.ack
                        {
                            let parsedMessage: Message = .TCPData(streamID, Data())
                            print("* No payload but receives an ack. Parsed the message as TCPData with no payload")
                            
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
        print("\n* Persona.handleParsedMessage()")
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
                    try await self.tcpProxy.processLocalPacket(conduit, packet)
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

    public func recordMessage(_ message: Message)
    {
        do
        {
            try self.save(identifier: self.recordID, codable: message)
            self.recordID = self.recordID + 1
        }
        catch
        {
            print("Could not record message")
        }
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
