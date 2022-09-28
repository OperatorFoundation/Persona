//
//  TCPStraw.swift
//  
//
//  Created by Dr. Brandon Wiley on 9/27/22.
//

import Foundation

import InternetProtocols
import Straw

public actor TCPStraw
{
    let straw = Straw()
    let window: Range<Int>

    public init(segmentStart: Int)
    {
        self.window = segmentStart..<(segmentStart+1)
    }

    public func write(_ segment: TCP)
    {
    }

    public func read() throws -> Data
    {
        throw TCPStrawError.unimplemented
    }

    public func read(size: Int) throws -> Data
    {
        throw TCPStrawError.unimplemented
    }

    public func read(maxSize: Int) throws -> Data
    {
        throw TCPStrawError.unimplemented
    }
}

public enum TCPStrawError: Error
{
    case unimplemented
}
