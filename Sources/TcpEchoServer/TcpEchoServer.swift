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
import SwiftHexTools
import TransmissionAsync

public class TcpEchoServer
{
    var tcpEchoLogger = Puppy()

    let echoTcpQueue = DispatchQueue(label: "EchoTcpQueue")

    let listenAddr: String
    let listenPort: Int
    #if os(macOS)
    let logger: os.Logger
    #else
    let logger: Logging.Logger
    #endif

    public init(listenAddr: String, listenPort: Int)
    {
        self.listenAddr = listenAddr
        self.listenPort = listenPort

#if os(macOS) || os(iOS)
        self.logger = Logger(subsystem: "org.OperatorFoundation.PersonaLogger", category: "TcpEchoServer")
#else
        self.logger = Logger(label: "org.OperatorFoundation.PersonaLogger")
#endif

        let logFileURL = File.homeDirectory().appendingPathComponent("PersonaTcpEcho.log", isDirectory: false)

        if File.exists(logFileURL.path)
        {
            let _ = File.delete(atPath: logFileURL.path)
        }

        if let file = try? FileLogger("TcpEchoServerLogger",
                                      logLevel: .debug,
                                      fileURL: logFileURL,
                                      filePermission: "600")  // Default permission is "640".
        {
            tcpEchoLogger.add(file)
        }

        tcpEchoLogger.debug("TcpEchoServer Start")
    }

    public func run() throws
    {
        let listener = try AsyncTcpSocketListener(host: self.listenAddr, port: self.listenPort, self.logger)

        while true
        {
            let connection: AsyncConnection = try AsyncAwaitThrowingSynchronizer<AsyncConnection>.sync
            {
                return try await listener.accept()
            }

            AsyncAwaitThrowingEffectSynchronizer.sync
            {
                try await self.handleTcpEchoConnection(connection: connection)
            }
        }
    }

    func handleTcpEchoConnection(connection: AsyncConnection) async throws
    {
        let received = try await connection.readSize(1)
        try await connection.write(received)
    }

    public func shutdown()
    {
    }
}

public enum TcpEchoServerError: Error
{
    case connectionClosed
    case echoListenerFailure
}
