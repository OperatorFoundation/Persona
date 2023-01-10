//
//  main.swift
//
//
//  Created by Dr. Brandon Wiley on 2/24/22.
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
import Nametag
import Net
import Spacetime
import Simulation
import Transmission

// run in one XCode window while you run the flower test in another
struct PersonaCommandLine: ParsableCommand
{
    static let clientConfigURL = URL(fileURLWithPath: File.homeDirectory().path).appendingPathComponent("persona-client.json")
    static let serverConfigURL = URL(fileURLWithPath: File.homeDirectory().path).appendingPathComponent("persona-server.json")
    
    static let configuration = CommandConfiguration(
        commandName: "persona",
        subcommands: [New.self, Run.self]
    )
}

extension PersonaCommandLine
{
    struct New: ParsableCommand
    {
        @Argument(help: "Human-readable name for your server to use in invites")
        var name: String

        @Argument(help: "Port on which to run the server")
        var port: Int
        
        @Argument(help: "optional IP address to listen on")
        var ip: String?

        mutating public func run() throws
        {
            let keychainDirectoryURL = File.homeDirectory().appendingPathComponent(".persona-server")
            let keychainLabel = "Persona.KeyAgreement"
            try Persona.generateNew(name: name, ip: ip, port: port, serverConfigURL: serverConfigURL, clientConfigURL: clientConfigURL, keychainURL: keychainDirectoryURL, keychainLabel: keychainLabel)
        }
    }
}

extension PersonaCommandLine
{
    struct Run: ParsableCommand
    {
        @Flag(help: "Record packets for later replay")
        var record: Bool = false

        @Flag(help: "Play back recorded packets")
        var play: Bool = false

        mutating func run() throws
        {
            guard let config = ServerConfig(url: serverConfigURL) else
            {
                throw RunCommandError.invalidConfigFile
            }
            
            let lifecycle = ServiceLifecycle()

            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            lifecycle.registerShutdown(label: "eventLoopGroup", .sync(eventLoopGroup.syncShutdownGracefully))

            let simulation: Simulation
            let universe: Persona
            switch (self.record, self.play)
            {
                case (true, true):
                    print("Packet recording and playback cannot be enabled at the same time.")
                    return

                case (true, false):
                    simulation = Simulation(capabilities: Capabilities(.display, .networkConnect, .networkListen, .persistence))
                    universe = Persona(listenAddr: config.host, listenPort: config.port, effects: simulation.effects, events: simulation.events, mode: .record)

                case (false, true):
                    simulation = Simulation(capabilities: Capabilities(.display, .networkConnect, .networkListen, .persistence))
                    universe = Persona(listenAddr: config.host, listenPort: config.port, effects: simulation.effects, events: simulation.events, mode: .playback)

                case (false, false):
                    simulation = Simulation(capabilities: Capabilities(.display, .networkConnect, .networkListen))
                    universe = Persona(listenAddr: config.host, listenPort: config.port, effects: simulation.effects, events: simulation.events, mode: .live)
            }

            lifecycle.register(label: "persona", start: .sync(universe.run), shutdown: .sync(universe.shutdown))

            lifecycle.start
            {
                error in

                if let error = error
                {
                    print("failed starting Persona ☠️: \(error)")
                }
                else
                {
                    print("Persona started successfully 🚀")
                }
            }

            lifecycle.wait()
        }
    }
}

PersonaCommandLine.main()

public enum ServerMode
{
    case live
    case playback
    case record
}

public enum NewCommandError: Error
{
    case couldNotGeneratePrivateKey
    case couldNotLoadKeychain
    case nametagError
    case portInUse(Int)
}

public enum RunCommandError: Error
{
    case invalidConfigFile
    case portInUse(Int)
}
