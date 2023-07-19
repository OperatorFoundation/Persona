//
//  main.swift
//  
//
//  Created by Dr. Brandon Wiley on 7/18/23.
//

import ArgumentParser
import Lifecycle
import Logging
import Foundation
import NIO
#if os(macOS) || os(iOS)
#else
import FoundationNetworking
#endif

import Gardener
import KeychainCli
import Net
import Persona
import Simulation
import Spacetime

// run in one XCode window while you run the flower test in another
struct TcpEchoServerCommandLine: ParsableCommand
{
    static let serverConfigURL = URL(fileURLWithPath: File.homeDirectory().path).appendingPathComponent("persona-server.json")

    static let configuration = CommandConfiguration(
        commandName: "tcpecho",
        subcommands: [Run.self]
    )
}

extension TcpEchoServerCommandLine
{
    struct Run: ParsableCommand
    {
        mutating func run() throws
        {
            guard let config = ServerConfig(url: serverConfigURL) else
            {
                throw TcpEchoServerErrorCommandLineError.invalidConfigFile
            }

            let lifecycle = ServiceLifecycle()

            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            lifecycle.registerShutdown(label: "eventLoopGroup", .sync(eventLoopGroup.syncShutdownGracefully))

            let simulation = Simulation(capabilities: Capabilities(.display, .networkConnect, .networkListen))
            let universe = TcpEchoServer(listenAddr: config.host, listenPort: config.port + 1, effects: simulation.effects, events: simulation.events)

            lifecycle.register(label: "tcpecho", start: .sync(universe.run), shutdown: .sync(universe.shutdown))

            lifecycle.start
            {
                error in

                if let error = error
                {
                    print("failed starting tcpecho ☠️: \(error)")
                }
                else
                {
                    print("tcpecho started successfully 🚀")
                }
            }

            lifecycle.wait()
        }
    }
}

TcpEchoServerCommandLine.main()

public enum TcpEchoServerErrorCommandLineError: Error
{
    case invalidConfigFile
    case portInUse(Int)
}
