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
    override public func pump() async throws -> TcpStateTransition
    {
        let serverIsStillOpen: Bool = try await self.pumpOnlyServerToStraw()
        var packets = try await self.pumpStrawToClient()

        if serverIsStillOpen
        {
            self.logger.debug("TcpCloseWait - server is still open, closing the upstream connection.")
            try await self.close()
        }

        // Send FIN
        let fin = try await makeFin()
        packets.append(fin)

        return TcpStateTransition(newState: TcpLastAck(self), packetsToSend: packets)
    }
}

public enum TcpCloseWaitError: Error
{
}
