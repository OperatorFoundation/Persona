//
//  Stats.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/15/23.
//

import Foundation

import Datable
import Gardener
import Puppy

public class Stats
{
    static let writeInterval: TimeInterval = 1 * 60 // 1 minute in seconds

    public var messages: Int = 0
    public var nonIPv4: Int = 0
    public var nonTcpUdpIPv4: Int = 0
    public var ipv4: Int = 0
    public var tcp: Int = 0
    public var udp: Int = 0

    var timer: Timer? = nil
    var logger: Puppy = Puppy()

    let logFileURL: URL

    public init() throws
    {
        self.logFileURL = File.homeDirectory().appendingPathComponent("/root/Persona/PersonaStats.log", isDirectory: false)
        if File.exists(self.logFileURL.path)
        {
            let _ = File.delete(atPath: self.logFileURL.path)
        }

        let file = try FileLogger("PersonaStatsLogger",
                                      logLevel: .debug,
                                      fileURL: self.logFileURL,
                                      filePermission: "600")  // Default permission is "640".
        self.logger.add(file)

        self.logger.info("Persona started")
    }

    public func writeLog()
    {
        self.logger.info("--------------")
        self.logger.info(self.description)
        self.logger.info("--------------")
    }
}

extension Stats: CustomStringConvertible
{
    public var description: String
    {
        return """
        non-IPv4         - \(self.nonIPv4)
        non-TCP/UDP IPv4 - \(self.nonTcpUdpIPv4)
        IPv4             - \(self.ipv4)
        IPv4/TCP         - \(self.tcp)
        IPv4/UDP         - \(self.udp)
        """
    }
}
