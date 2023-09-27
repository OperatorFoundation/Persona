//
//  TcpNew.swift
//  
//
//  Created by Dr. Brandon Wiley on 9/25/23.
//

import Foundation

import InternetProtocols

// A special state not in the TCP RFC that is needed for a proxying application.
// TCP connections in the NEW state have received a SYN, but we can't process it according to the TCP state flow chart yet.
// Before we can process a SYN, we need to check if the upstream server will accept a connection.
// This is handled by the special NEW state.
public class TcpNew: TcpStateHandler
{
    // Quietly ignore all incoming packets, we're waiting to hear back on our upstream connection attempt.
    override public func processDownstreamPacket(stats: Stats, ipv4: IPv4, tcp: TCP, payload: Data?) async throws -> TcpStateTransition
    {
        stats.new = stats.new + 1

        return TcpStateTransition(newState: self)
    }

    // Success, now we can process the SYN and progress through the normal TCP state machine.
    override public func processUpstreamConnectSuccess() async throws -> TcpStateTransition
    {
        return TcpStateTransition(newState: TcpListen(self))
    }

    // Failure, we cannot accept packets for this destination. Close the socket and reject all incoming packets.
    override public func processUpstreamConnectFailure() async throws -> TcpStateTransition
    {
        return TcpStateTransition(newState: TcpClosed(self))
    }
}

