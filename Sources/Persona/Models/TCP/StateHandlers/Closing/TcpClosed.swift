//
//  TcpClosed.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/6/23.
//

import Foundation
import Logging

import InternetProtocols
import Puppy

// FIXME me - implement this state
public class TcpClosed: TcpStateHandler
{
    override public var description: String
    {
        return "[TcpClosed]"
    }

    public override init(identity: TcpIdentity, logger: Logger, tcpLogger: Puppy, writeLogger: Puppy)
    {
        super.init(identity: identity, logger: logger, tcpLogger: tcpLogger, writeLogger: writeLogger)

        self.open = false
    }

    public override init(_ oldState: TcpStateHandler)
    {
        super.init(oldState)

        self.open = false
    }

    public func processDownstreamPacket(ipv4: IPv4, tcp: TCP, payload: Data?) async throws
    {
    }

    public func processUpstreamData(data: Data) async throws
    {
    }
}

public enum TcpClosedError: Error
{
}
