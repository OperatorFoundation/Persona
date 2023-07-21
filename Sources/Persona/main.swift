//
//  main.swift
//
//
//  Created by Dr. Brandon Wiley on 2/24/22.
//

import Logging
import FileLogging
import LoggingSyslog
import Foundation
#if os(macOS) || os(iOS)
#else
import FoundationNetworking
#endif

LoggingSystem.bootstrap(SyslogLogHandler.init)

let persona = Persona()
try await persona.run()
