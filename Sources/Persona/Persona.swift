//
//  Persona.swift
//  
//
//  Created by Dr. Brandon Wiley on 2/24/22.
//

import Chord
import Flower
import Foundation
import InternetProtocols
import Net
import Spacetime
import SwiftHexTools
import Transmission
import TransmissionTypes
import Universe

public class Persona: Universe
{
    let connectionsQueue = DispatchQueue(label: "ConnectionsQueue")
    let echoUdpQueue = DispatchQueue(label: "EchoUdpQueue")
    let echoTcpQueue = DispatchQueue(label: "EchoTcpQueue")
    let echoTcpConnectionQueue = DispatchQueue(label: "EchoTcpConnectionQueue")

    var pool = AddressPool()
    var conduitCollection = ConduitCollection()
    
    var listenAddr = "0.0.0.0"
    var listenPort = 1234
    var echoPort = 2233

    var udpProxy: UdpProxy! = nil
    var tcpProxy: TcpProxy! = nil

    public override init(effects: BlockingQueue<Effect>, events: BlockingQueue<Event>)
    {
        super.init(effects: effects, events: events)

        self.udpProxy = UdpProxy(universe: self)
        self.tcpProxy = TcpProxy(universe: self, quietTime: false)
    }

    public override func main() throws
    {
        let echoUdpListener = try self.listen(listenAddr, echoPort, type: .udp)

        // MARK: async cannot be replaces with Task because it is not currently supported on Linux
        echoUdpQueue.async
        {
            do
            {
                try self.handleUdpEchoListener(echoListener: echoUdpListener)
            }
            catch
            {
                print("echo listener failed")
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
            
            // MARK: async cannot be replaces with Task because it is not currently supported on Linux
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
            display("New echo connection")
            
            guard let received = connection.read(size: 19) else
            {
                display("Echo server failed to read 19 bytes, continuing with this connection")
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
            
            display("Echo received a message: \(received.string)")
            
            guard connection.write(string: "Hello catbus ᓚᘏᗢ") else
            {
                display("Echo server failed to write a response, continuing with this connection.")
                continue
            }
        }
    }

    func handleTcpEchoListener(echoListener: TransmissionTypes.Listener) throws
    {
        while true
        {
            let connection = try echoListener.accept()
            display("New echo connection")

            self.echoTcpConnectionQueue.async
            {
                self.handleTcpEchoConnection(connection: connection)
            }
        }
    }

    func handleTcpEchoConnection(connection: TransmissionTypes.Connection)
    {
        guard let received = connection.read(maxSize: 1024) else
        {
            display("TCP Echo server failed to read bytes, continuing with this connection, closing")
            connection.close()
            return
        }

        display("Echo received a message: \(received) - \(received.hex)")

        guard connection.write(data: received) else
        {
            display("TCP Echo server failed to write a response, continuing with this connection, closing")
            connection.close()
            return
        }
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
            
            address = try self.handleFirstMessage(flowerConnection)
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
    func handleFirstMessage(_ flowerConnection: FlowerConnection) throws -> IPv4Address
    {
        print("Persona.handleFirstMessage() called")
        guard let message = flowerConnection.readMessage() else
        {
            print("Connection closed")
            throw PersonaError.connectionClosed
        }

        print("Persona.handleFirstMessage: received an \(message.description)")
        
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
        print("Persona.handleNextMessage() called")
        guard let message = flowerConnection.readMessage() else
        {
            print("Failed to read message")

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
        
        print("Persona.handleNextMessage: received a \(message.description)")
        
        switch message
        {
            case .IPDataV4(let data):
                let packet = Packet(ipv4Bytes: data, timestamp: Date(), debugPrints: true)
                print(" * handleNextMessage created an IPV4 packet")
                guard let ipv4Packet = packet.ipv4 else
                {
                    // Drop this packet, but then continue processing more packets
                    throw PersonaError.packetNotIPv4(data)
                }

                if let tcp = packet.tcp
                {
                    guard let ipv4Destination = IPv4Address(data: ipv4Packet.destinationAddress) else
                    {
                        // Drop this packet, but then continue processing more packets
                        throw PersonaError.addressDataIsNotIPv4(ipv4Packet.destinationAddress)
                    }
                    
                    guard let ipv4Source = IPv4Address(data: ipv4Packet.sourceAddress) else
                    {
                        // Drop this packet, but then continue processing more packets
                        throw PersonaError.addressDataIsNotIPv4(ipv4Packet.destinationAddress)
                    }

                    let destinationPort = NWEndpoint.Port(integerLiteral: tcp.destinationPort)
                    let destinationEndpoint = EndpointV4(host: ipv4Destination, port: destinationPort)
                    
                    let sourcePort = NWEndpoint.Port(integerLiteral: tcp.sourcePort)
                    let sourceEndpoint = EndpointV4(host: ipv4Source, port: sourcePort)
                    
                    let streamID = generateStreamID(source: sourceEndpoint, destination: destinationEndpoint)
                    let parsedMessage: Message
                    
                    if tcp.syn
                    {
                        parsedMessage = .TCPOpenV4(destinationEndpoint, streamID)
                    }
                    else if tcp.rst
                    {
                        parsedMessage = .TCPClose(streamID)
                    }
                    else
                    {
                        guard let payload = tcp.payload else
                        {
                            throw PersonaError.emptyPayload
                        }
                        
                        parsedMessage = .TCPData(streamID, payload)
                    }
                    
                    try self.handleParsedMessage(address, parsedMessage, packet)
                }
                if let udp = packet.udp
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
                else
                {
                    // Drop this packet, but then continue processing more packets
                    throw PersonaError.unsupportedPacketType(data)
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
        print("handleParsedMessage(\(message.description))")
        switch message
        {
            case .UDPDataV4(_, _):
                guard let conduit = self.conduitCollection.getConduit(with: address.string) else
                {
                    print("Unknown conduit address \(address)")
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
                throw PersonaError.unsupportedParsedMessage(message)
                
            case .TCPOpenV4(_, _), .TCPData(_, _), .TCPClose(_):
                guard let conduit = self.conduitCollection.getConduit(with: address.string) else
                {
                    print("Unknown conduit address \(address)")
                    return
                }
                
                try self.tcpProxy.processLocalPacket(conduit, packet)
                
            default:
                throw PersonaError.unsupportedParsedMessage(message)
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
