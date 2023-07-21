//
//  ClientConfig.swift
//  
//
//  Created by Dr. Brandon Wiley on 11/7/22.
//

import Foundation

import KeychainCli
import Gardener

public struct ClientConfig: Codable
{
    public let name: String
    public let host: String
    public let port: Int
    public let serverPublicKey: PublicKey

    public init(name: String, host: String, port: Int, serverPublicKey: PublicKey)
    {
        self.name = name
        self.host = host
        self.port = port
        self.serverPublicKey = serverPublicKey
    }
    
    init?(from data: Data)
    {
        let decoder = JSONDecoder()
        do
        {
            let decoded = try decoder.decode(ClientConfig.self, from: data)
            self = decoded
        }
        catch
        {
            return nil
        }
    }
    
    public init?(path: String)
    {
        let url = URL(fileURLWithPath: path)
        
        self.init(url: url)
    }
    
    public init?(url: URL)
    {
        do
        {
            let data = try Data(contentsOf: url)
            self.init(from: data)
        }
        catch
        {
            return nil
        }
    }
    
    public func save(to fileURL: URL) throws
    {
        let encoder = JSONEncoder()
        let serverConfigData = try encoder.encode(self)
        try serverConfigData.write(to: fileURL)
    }
}
