//
//  main.swift
//
//
//  Created by Dr. Brandon Wiley on 2/24/22.
//

import ArgumentParser
import Foundation
#if os(macOS) || os(iOS)
#else
import FoundationNetworking
#endif

// The main entry point for Persona uses ArgumentParser to create a command line interface.
// It only supports one flag, -socket, which is used to run Persona without the router, only
// for testing purposes. In production deployment, it is intended to be run by the router.
struct PersonaCommandLine: ParsableCommand
{
    @Flag // Enable single connection socket-based mode, designed for testing
    var socket: Bool = false // By default, use router mode

    mutating func run() throws
    {
        print("Persona is go!")

        let socketOption = socket

        // FIXME - migrate to AsyncParsableCommand to remove this lock.
        let lock: DispatchSemaphore = DispatchSemaphore(value: 0)

        Task
        {
            let persona = try await Persona(socket: socketOption)
            try await persona.run()
            lock.signal()
        }

        lock.wait()

        print("exiting abnormally, something forgot to wait")
    }
}

PersonaCommandLine.main()
