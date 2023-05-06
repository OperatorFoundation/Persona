//
//  ClientConfig.swift
//  
//
//  Created by Dr. Brandon Wiley on 11/7/22.
//

import Foundation

import Keychain
import Gardener

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
            print("* Persona.ClientConfig: Error received while attempting to decode a server configuration json file: \(error)")
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
            print("* Persona.ClientConfig: Error decoding client config file: \(error)")
            
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
