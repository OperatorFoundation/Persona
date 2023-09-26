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

struct PersonaCommandLine: ParsableCommand
{
    @Flag // Enable single connection socket-based mode, designed for testing
    var socket: Bool = false // By default, use systemd mode

    mutating func run() throws
    {
        print("Persona is go!")

        let socketOption = socket

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
