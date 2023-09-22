//
//  TcpStateTransition.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/6/23.
//

import Foundation

import InternetProtocols

public struct TcpStateTransition
{
    public let newState: TcpStateHandler
    public let packetsToSend: [IPv4]
    public let progress: Bool

    public init(newState: TcpStateHandler, packetsToSend: [IPv4] = [], progress: Bool = false)
    {
        self.newState = newState
        self.packetsToSend = packetsToSend
        self.progress = progress
    }
}
