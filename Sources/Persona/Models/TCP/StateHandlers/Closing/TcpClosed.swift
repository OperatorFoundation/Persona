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
import TransmissionAsync

// FIXME me - implement this state
public class TcpClosed: TcpStateHandler
{
    public override init(identity: Identity, downstream: AsyncConnection, logger: Logger, tcpLogger: Puppy, writeLogger: Puppy)
    {
        super.init(identity: identity, downstream: downstream, logger: logger, tcpLogger: tcpLogger, writeLogger: writeLogger)

        self.open = false
    }

    public override init(_ oldState: TcpStateHandler)
    {
        super.init(oldState)

        self.open = false
    }
}

public enum TcpClosedError: Error
{
}
