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

    let logger: Puppy

    public init(logger: Puppy)
    {
        self.logger = logger
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
