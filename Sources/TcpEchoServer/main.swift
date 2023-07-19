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
let logger = Logger(subsystem: "Persona", category: "TcpEchoServer")
#else
let logger = Logger(label: "TcpEchoServer")
#endif

let connection = AsyncStdioConnection(logger)

while true
{
    do
    {
        let data = try await connection.readSize(1)
        try await connection.write(data)
    }
    catch
    {
        exit(0)
    }
}
