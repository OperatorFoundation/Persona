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

    public var closed: Int = 0
    public var closeWait: Int = 0
    public var closing: Int = 0
    public var finWait1: Int = 0
    public var finWait2: Int = 0
    public var lastAck: Int = 0
    public var listen: Int = 0
    public var new: Int = 0
    public var synReceived: Int = 0
    public var synSent: Int = 0
    public var established: Int = 0

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
        \tIPv4/UDP         - \(self.udp)
        \tIPv4/TCP         - \(self.tcp)
        \t\tCLOSED         - \(self.closed)
        \t\tCLOSE-WAIT     - \(self.closeWait)
        \t\tCLOSINGvvv     - \(self.closing)
        \t\tFIN-WAIT-1     - \(self.finWait1)
        \t\tFIN-WAIT-2     - \(self.finWait2)
        \t\tLAST-ACK        - \(self.lastAck)
        \t\tNEW            - \(self.new)
        \t\tSYN-RECEIVED   - \(self.synReceived)
        \t\tSYN-SENT       - \(self.synSent)
        \t\tESTABLISHED    - \(self.established)
        """
    }
}
