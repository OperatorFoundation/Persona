//
//  ServerConfig.swift
//  
//
//  Created by Dr. Brandon Wiley on 11/7/22.
//

import Foundation

public struct ServerConfig: Codable
{
    let name: String
    let host: String
    let port: Int

    public init(name: String, host: String, port: Int)
    {
        self.name = name
        self.host = host
        self.port = port
    }
}
