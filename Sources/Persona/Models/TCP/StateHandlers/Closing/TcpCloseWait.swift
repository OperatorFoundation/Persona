//
//  TcpCloseWait.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/6/23.
//

import Foundation

import InternetProtocols

/// CLOSE-WAIT - represents waiting for a connection termination request  the local user.
///
/// CLOSE-WAIT means we have received a FIN from the client.
/// No more data will be arriving from the client.
/// We will keep checking on if there is more data from the server
///
public class TcpCloseWait: TcpStateHandler
{
    override public func processDownstreamPacket(ipv4: IPv4, tcp: TCP, payload: Data?) async throws -> TcpStateTransition 
    {
        // FIXME:
        if tcp.fin
        {
            let ack = try await makeAck()
            return TcpStateTransition(newState: self, packetsToSend: [ack])
        }
        
        return TcpStateTransition(newState: self)
    }
    
    override public func processUpstreamData(data: Data) async throws -> TcpStateTransition
    {
        try self.straw.write(data)

        let packets = try await self.pumpStrawToClient()

        return TcpStateTransition(newState: self, packetsToSend: packets)
    }
    
    override public func processUpstreamClose() async throws -> TcpStateTransition
    {
        var packets = try await self.pumpStrawToClient()
        
        // Send FIN
        let fin = try await makeFinAck()
        packets.append(fin)
        
        return TcpStateTransition(newState: TcpLastAck(self), packetsToSend: packets)
    }
}

public enum TcpCloseWaitError: Error
{
}
