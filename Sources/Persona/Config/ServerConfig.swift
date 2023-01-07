//
//  ServerConfig.swift
//  
//
//  Created by Dr. Brandon Wiley on 11/7/22.
//

import Foundation
import Gardener

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
    
    init?(from data: Data)
    {
        let decoder = JSONDecoder()
        do
        {
            let decoded = try decoder.decode(ServerConfig.self, from: data)
            self = decoded
        }
        catch
        {
            print("Error received while attempting to decode a server configuration json file: \(error)")
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
            print("Error decoding server config file: \(error)")
            
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
