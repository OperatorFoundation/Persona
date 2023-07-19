//
//  main.swift
//
//
//  Created by Dr. Brandon Wiley on 7/19/23.
//

#if os(macOS) || os(iOS)
import os.log
#else
import Logging
#endif
import Foundation

import TransmissionAsync

#if os(macOS)
let logger = Logger(subsystem: "Persona", category: "UdpEchoServer")
#else
let logger = Logger(label: "UdpEchoServer")
#endif

let connection = AsyncStdioConnection(logger)

while true
{
    do
    {
        let data = try await connection.read()
        try await connection.write(data)
    }
    catch
    {
        exit(0)
    }
}
