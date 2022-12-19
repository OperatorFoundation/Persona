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
import Keychain
import Nametag
import Net
import Spacetime
import Simulation
import Transmission

// run in one XCode window while you run the flower test in another
struct PersonaCommandLine: ParsableCommand
{
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

        mutating public func run() throws
        {
            let ip: String = try Ipify.getPublicIP()

            if let test = TransmissionConnection(host: ip, port: port)
            {
                test.close()

                throw NewCommandError.portInUse(port)
            }

            #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
            let keychain = Keychain()
            #else
            guard let keychain = Keychain(baseDirectory: File.homeDirectory().appendingPathComponent(".persona-server")) else
            {
                throw NewCommandError.couldNotLoadKeychain
            }
            #endif

            guard let privateKeyKeyAgreement = keychain.generateAndSavePrivateKey(label: "Persona.KeyAgreement", type: .P256KeyAgreement) else
            {
                throw NewCommandError.couldNotGeneratePrivateKey
            }

            let encoder = JSONEncoder()

            let serverConfig = ServerConfig(name: name, host: ip, port: port)
            let serverConfigData = try encoder.encode(serverConfig)
            let serverConfigURL = URL(fileURLWithPath: File.homeDirectory().path).appendingPathComponent("persona-server.json")
            try serverConfigData.write(to: serverConfigURL)
            print("Wrote config to \(serverConfigURL.path)")

            let publicKeyKeyAgreement = privateKeyKeyAgreement.publicKey
            let clientConfig = ClientConfig(name: name, host: ip, port: port, serverPublicKey: publicKeyKeyAgreement)
            let clientConfigData = try encoder.encode(clientConfig)
            let clientConfigURL = URL(fileURLWithPath: File.currentDirectory()).appendingPathComponent("persona-client.json")
            try clientConfigData.write(to: clientConfigURL)
            print("Wrote config to \(clientConfigURL.path)")
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
            let configURL = URL(fileURLWithPath: File.homeDirectory().path).appendingPathComponent("persona-server.json")
            let configData = try Data(contentsOf: configURL)
            let decoder = JSONDecoder()
            let config = try decoder.decode(ServerConfig.self, from: configData)
            print("Read config from \(configURL.path)")

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
