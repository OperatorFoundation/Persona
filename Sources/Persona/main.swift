//
//  main.swift
//
//
//  Created by Dr. Brandon Wiley on 2/24/22.
//

import FileLogging
import Foundation
#if os(macOS) || os(iOS)
#else
import FoundationNetworking
#endif
import HeliumLogger
import Logging

let logger = HeliumLogger(.entry)
LoggingSystem.bootstrap(logger.makeLogHandler)

let persona = try Persona()
try await persona.run()
