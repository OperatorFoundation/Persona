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
import PersonaConfig
import Simulation
import Spacetime

// run in one XCode window while you run the flower test in another
struct UdpEchoServerCommandLine: ParsableCommand
{
    static let serverConfigURL = URL(fileURLWithPath: File.homeDirectory().path).appendingPathComponent("persona-server.json")

    static let configuration = CommandConfiguration(
        commandName: "udpecho",
        subcommands: [Run.self]
    )
}

extension UdpEchoServerCommandLine
{
    struct Run: ParsableCommand
    {
        mutating func run() throws
        {
            guard let config = ServerConfig(url: serverConfigURL) else
            {
                throw UdpEchoServerErrorCommandLineError.invalidConfigFile
            }

            let lifecycle = ServiceLifecycle()

            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            lifecycle.registerShutdown(label: "eventLoopGroup", .sync(eventLoopGroup.syncShutdownGracefully))

            let simulation = Simulation(capabilities: Capabilities(.display, .networkConnect, .networkListen))
            let universe = UdpEchoServer(listenAddr: config.host, listenPort: config.port + 1, effects: simulation.effects, events: simulation.events)

            lifecycle.register(label: "udpecho", start: .sync(universe.run), shutdown: .sync(universe.shutdown))

            lifecycle.start
            {
                error in

                if let error = error
                {
                    print("failed starting udpecho ☠️: \(error)")
                }
                else
                {
                    print("udpecho started successfully 🚀")
                }
            }

            lifecycle.wait()
        }
    }
}

UdpEchoServerCommandLine.main()

public enum UdpEchoServerErrorCommandLineError: Error
{
    case invalidConfigFile
    case portInUse(Int)
}
