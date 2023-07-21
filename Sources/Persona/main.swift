//
//  main.swift
//
//
//  Created by Dr. Brandon Wiley on 2/24/22.
//

import Foundation
#if os(macOS) || os(iOS)
#else
import FoundationNetworking
#endif

let persona = try Persona()
try await persona.run()
