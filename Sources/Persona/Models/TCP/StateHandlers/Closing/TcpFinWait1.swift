//
//  TcpFinWait1.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/5/23.
//

import Foundation

import InternetProtocols

// FIXME me - implement this state
public class TcpFinWait1: TcpStateHandler
{
    public func processDownstreamPacket(ipv4: IPv4, tcp: TCP, payload: Data?) async throws
    {
    }

    public func processUpstreamData(data: Data) async throws
    {
    }
}

public enum TcpFinWait1Error: Error
{
}
