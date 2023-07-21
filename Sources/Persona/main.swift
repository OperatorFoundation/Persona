//
//  main.swift
//
//
//  Created by Dr. Brandon Wiley on 2/24/22.
//

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

let persona = Persona()
try await persona.run()
