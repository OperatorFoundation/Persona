//
//  TcpEchoServer.swift
//  
//
//  Created by Dr. Brandon Wiley on 7/18/23.
//

import Foundation
#if os(macOS) || os(iOS)
import os.log
#else
import Logging
#endif

import Chord
import Gardener
import Puppy
import Spacetime
import SwiftHexTools
import Transmission
import TransmissionTypes
import Universe

public class TcpEchoServer: Universe
{
    var udpEchoLogger = Puppy()

    let echoUdpQueue = DispatchQueue(label: "EchoUdpQueue")

    let listenAddr: String
    let listenPort: Int

    public init(listenAddr: String, listenPort: Int, effects: BlockingQueue<Effect>, events: BlockingQueue<Event>)
    {
        self.listenAddr = listenAddr
        self.listenPort = listenPort

#if os(macOS) || os(iOS)
        let logger = Logger(subsystem: "org.OperatorFoundation.PersonaLogger", category: "Persona")
#else
        let logger = Logger(label: "org.OperatorFoundation.PersonaLogger")
#endif

        let logFileURL = File.homeDirectory().appendingPathComponent("PersonaUdpEcho.log", isDirectory: false)

        if File.exists(logFileURL.path)
        {
            let _ = File.delete(atPath: logFileURL.path)
        }

        if let file = try? FileLogger("UdpEchoServerLogger",
                                      logLevel: .debug,
                                      fileURL: logFileURL,
                                      filePermission: "600")  // Default permission is "640".
        {
            udpEchoLogger.add(file)
        }

        udpEchoLogger.debug("UdpEchoServer Start")

        super.init(effects: effects, events: events, logger: logger)
    }

    public override func main() throws
    {
        let echoUdpListener = try self.listen(listenAddr, listenPort, type: .udp)

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

    public func shutdown()
    {
    }
}

public enum UdpEchoServerError: Error
{
    case connectionClosed
    case echoListenerFailure
}
