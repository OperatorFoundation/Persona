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

import Spacetime
import Simulation

// run in one XCode window while you run the flower test in another
struct PersonaCommandLine: ParsableCommand
{
    static let configuration = CommandConfiguration(
        commandName: "persona",
        subcommands: [New.self, Run.self]
    )
}

struct New: ParsableCommand
{
    @Argument(help: "Human-readable name for your server to use in invites")
    var name: String

    @Argument(help: "Port on which to run the server")
    var port: Int

    mutating public func run() throws
    {
//        let ip: String = try Ipify.getPublicIP()
//
//        if let test = TransmissionConnection(host: ip, port: port)
//        {
//            test.close()
//
//            throw NewCommandError.portInUse
//        }
//
//        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
//        let keychain = Keychain()
//        #else
//        guard let keychain = Keychain(baseDirectory: File.homeDirectory().appendingPathComponent(".rendezvous-server")) else
//        {
//            throw NewCommandError.couldNotLoadKeychain
//        }
//        #endif
//
//        guard let privateKeyKeyAgreement = keychain.generateAndSavePrivateKey(label: "Rendezvous.KeyAgreement", type: .P256KeyAgreement) else
//        {
//            throw NewCommandError.couldNotGeneratePrivateKey
//        }
//
//        guard let nametag = Nametag() else
//        {
//            throw NewCommandError.nametagError
//        }
//
//        let privateIdentity = try PrivateIdentity(keyAgreement: privateKeyKeyAgreement, nametag: nametag)
//        let publicIdentity = privateIdentity.publicIdentity
//
//        let config = Config(name: name, host: ip, port: port, identity: publicIdentity)
//        let encoder = JSONEncoder()
//        let configData = try encoder.encode(config)
//        let configURL = URL(fileURLWithPath: File.currentDirectory()).appendingPathComponent("rendezvous-config.json")
//        try configData.write(to: configURL)
//        print("Wrote config to \(configURL.path)")
    }
}

struct Run: ParsableCommand
{
    @Flag(help: "Record packets for later replay")
    var record: Bool = false

    @Flag(help: "Play back recorded packets")
    var play: Bool = false

    mutating func run() throws
    {
        let logger = Logger(label: "Persona")

//        let configURL = URL(fileURLWithPath: File.currentDirectory()).appendingPathComponent("rendezvous-config.json")
//        let configData = try Data(contentsOf: configURL)
//        let decoder = JSONDecoder()
//        let config = try decoder.decode(Config.self, from: configData)
//        print("Read config from \(configURL.path)")

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
                universe = Persona(effects: simulation.effects, events: simulation.events, mode: .record)

            case (false, true):
                simulation = Simulation(capabilities: Capabilities(.display, .networkConnect, .networkListen, .persistence))
                universe = Persona(effects: simulation.effects, events: simulation.events, mode: .playback)

            case (false, false):
                simulation = Simulation(capabilities: Capabilities(.display, .networkConnect, .networkListen))
                universe = Persona(effects: simulation.effects, events: simulation.events, mode: .live)
        }

        lifecycle.register(label: "persona", start: .sync(universe.run), shutdown: .sync(universe.shutdown))

        lifecycle.start
        {
            error in

            if let error = error
            {
                logger.error("failed starting Persona ☠️: \(error)")
            }
            else
            {
                logger.info("Persona started successfully 🚀")
            }
        }

        lifecycle.wait()
    }
}

public enum ServerMode
{
    case live
    case playback
    case record
}
