//
//  ClientConfig.swift
//  
//
//  Created by Dr. Brandon Wiley on 11/7/22.
//

import Foundation

import Keychain

public struct ClientConfig: Codable
{
    let name: String
    let host: String
    let port: Int
    let serverPublicKey: PublicKey

    public init(name: String, host: String, port: Int, serverPublicKey: PublicKey)
    {
        self.name = name
        self.host = host
        self.port = port
        self.serverPublicKey = serverPublicKey
    }
}
