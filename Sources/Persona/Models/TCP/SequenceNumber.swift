//
//  SequenceNumber.swift
//  
//
//  Created by Dr. Brandon Wiley on 3/2/22.
//

import Foundation

public struct SequenceNumber: Equatable, Comparable
{
    static public let max: SequenceNumber = SequenceNumber(UInt32.max - 1)

    static public func ==(_ x: SequenceNumber, _ y: SequenceNumber) -> Bool
    {
        return x.uint32 == y.uint32
    }

    static public func <(_ x: SequenceNumber, _ y: SequenceNumber) -> Bool
    {
        return (y - x) < (x - y)
    }

    static public func -(_ x: SequenceNumber, _ y: SequenceNumber) -> UInt32
    {
        if x.uint32 == y.uint32
        {
            return 0
        }
        else if x.uint32 > y.uint32
        {
            return x.uint32 - y.uint32
        }
        else
        {
            return x.uint32 + (SequenceNumber.max.uint32 - y.uint32)
        }
    }

    public let uint32: UInt32

    public init(_ uint32: UInt32)
    {
        self.uint32 = UInt32(uint32)
    }

    public init(_ data: Data)
    {
        let uint32 = data.maybeNetworkUint32!
        self.init(uint32)
    }

    public func add(_ x: Int) -> SequenceNumber
    {
        var newUint64 = UInt64(self.uint32) + UInt64(x)
        if newUint64 > UInt32.max
        {
            newUint64 = newUint64 - UInt64(UInt32.max)
        }

        return SequenceNumber(UInt32(newUint64))
    }

    public func increment() -> SequenceNumber
    {
        var newUint32 = self.uint32 + 1
        if newUint32 == UInt32.max
        {
            newUint32 = 0
        }

        return SequenceNumber(newUint32)
    }
}
