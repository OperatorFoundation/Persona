//
//  TcpClosing.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/6/23.
//

import Foundation

import InternetProtocols

// FIXME me - implement this state
public class TcpClosing: TcpStateHandler
{
    override public var description: String
    {
        return "[TcpClosing]"
    }

    public func processDownstreamPacket(ipv4: IPv4, tcp: TCP, payload: Data?) async throws
    {
    }

    public func processUpstreamData(data: Data) async throws
    {
    }
}

public enum TcpClosingError: Error
{
}
