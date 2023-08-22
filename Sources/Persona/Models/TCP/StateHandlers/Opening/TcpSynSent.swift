//
//  TcpSynSent.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/5/23.
//

import Foundation

import InternetProtocols

// This state is not supported.
public class TcpSynSent: TcpStateHandler
{
    override public var description: String
    {
        return "[TcpSynSent]"
    }
}

public enum TcpSynSentError: Error
{
}
