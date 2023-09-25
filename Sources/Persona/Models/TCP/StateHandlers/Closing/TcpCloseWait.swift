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
    override public func processUpstreamData(data: Data) async throws -> TcpStateTransition
    {
        if self.straw.isEmpty
        {
            if data.count > 0
            {
                try self.straw.write(data)
                self.logger.debug("TcpEstablished.processUpstreamData: Persona <-- tcpproxy - \(data.count) bytes")
            }
            else
            {
                self.logger.debug("TcpEstablished.processUpstreamData: Persona <-- tcpproxy - no data")
            }
        }

        var packets = try await self.pumpStrawToClient()

        if packets.isEmpty
        {
            let ack = try await makeAck()
            packets.append(ack)
        }

        self.logger.debug("TcpCloseWait - server is still open, closing the upstream connection.")
        try await self.close()

        // Send FIN
        let fin = try await makeFin()
        packets.append(fin)

        return TcpStateTransition(newState: TcpLastAck(self), packetsToSend: packets)
    }

    override public func processUpstreamClose() async throws -> TcpStateTransition
    {
        return TcpStateTransition(newState: TcpLastAck(self))
    }
}

public enum TcpCloseWaitError: Error
{
}
