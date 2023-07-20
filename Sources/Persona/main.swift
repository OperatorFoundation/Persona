//
//  main.swift
//
//
//  Created by Dr. Brandon Wiley on 2/24/22.
//

import ArgumentParser
#if os(macOS)
import os.log
#else
import Logging
#endif
import Foundation
#if os(macOS) || os(iOS)
#else
import FoundationNetworking
#endif

import Gardener
import KeychainCli

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
        mutating func run() async throws
        {
            let persona = Persona()
            try await persona.run()
        }
    }
}

PersonaCommandLine.main()

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
