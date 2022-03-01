//
//  Persona.swift
//  
//
//  Created by Dr. Brandon Wiley on 2/24/22.
//

import Flower
import Foundation
import InternetProtocols
import Net
// transmission, but with effects under the hood
import TransmissionTypes
import Universe

public class Persona: Universe
{
    var pool = AddressPool()
    var conduitCollection = ConduitCollection()

    public override func main() throws
    {
        display("listening on 127.0.0.1 1234")
        let listener = try self.listen("127.0.0.1", 1234)

        while true
        {
            let connection = listener.accept()
            display("New connection")

            Task
            {
                handleIncomingConnection(connection)
            }
        }
    }

    // takes a transmission connection and wraps as a flower connection
    func handleIncomingConnection(_ connection: TransmissionTypes.Connection)
    {
        // FIXME - add logging
        let flowerConnection = FlowerConnection(connection: connection, log: nil)

        do
        {
            try self.handleFirstMessage(flowerConnection)
        }
        catch
        {
            return
        }

        while true
        {
            do
            {
                try self.handleNextMessage(flowerConnection)
            }
            catch
            {
                continue
            }
        }
    }

    // deals with IP assignment
    func handleFirstMessage(_ flowerConnection: FlowerConnection) throws
    {
        guard let message = flowerConnection.readMessage() else
        {
            print("Connection closed")
            throw PersonaError.connectionClosed
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

                flowerConnection.writeMessage(message: .IPAssignV4(ipv4))

                return
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
    func handleNextMessage(_ flowerConnection: FlowerConnection) throws
    {
        guard let message = flowerConnection.readMessage() else
        {
            print("Connection closed")
            throw PersonaError.connectionClosed
        }

        switch message
        {
            case .IPDataV4(let data):
                let packet = Packet(ipv4Bytes: data, timestamp: Date(), debugPrints: true)
                guard let ipv4 = packet.ipv4 else
                {
                    // Drop this packet, but then continue processing more packets
                    throw PersonaError.packetNotIPv4(data)
                }

//                if let tcp = packet.tcp
//                {
//                    // FIXME - implement TCP
//                    return
//                }
                /*else*/ if let udp = packet.udp
                {
                    guard let ipv4 = IPv4Address(data: ipv4.destinationAddress) else
                    {
                        // Drop this packet, but then continue processing more packets
                        throw PersonaError.addressDataIsNotIPv4(ipv4.destinationAddress)
                    }

                    let port = NWEndpoint.Port(integerLiteral: udp.destinationPort)
                    let endpoint = EndpointV4(host: ipv4, port: port)
                    guard let payload = udp.payload else
                    {
                        throw PersonaError.emptyPayload
                    }

                    let parsedMessage: Message = .UDPDataV4(endpoint, payload)
                    try self.handleParsedMessage(parsedMessage)
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
    func handleParsedMessage(_ message: Message) throws
    {
        print("handleParsedMessage(\(message.description))")
        switch message
        {
            case .UDPDataV4(let endpoint, let data):
                let addressData = endpoint.host.rawValue
                let addressString = "\(addressData[0]).\(addressData[1]).\(addressData[2]).\(addressData[3])"
                let port = Int(endpoint.port.rawValue)
                let connection = try self.connect(addressString, port, ConnectionType.udp)
                let success = connection.write(data: data)
                if !success
                {
                    print("Failed write")
                }

                // FIXME - close connection

            case .UDPDataV6(_, _):
                throw PersonaError.unsupportedParsedMessage(message)

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
}
