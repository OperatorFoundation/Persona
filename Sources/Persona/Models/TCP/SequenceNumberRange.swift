//
//  SequenceNumberRange.swift
//  
//
//  Created by Dr. Brandon Wiley on 12/13/22.
//

import Foundation

import InternetProtocols

public class SequenceNumberRange
{
    public var lowerBound: SequenceNumber
    public var upperBound: SequenceNumber

    public var size: UInt16
    {
        if lowerBound < upperBound
        {
            return UInt16(upperBound.uint32 - lowerBound.uint32)
        }
        else
        {
            return UInt16((upperBound.uint32 + UInt32(UInt16.max)) - lowerBound.uint32)
        }
    }

    public init(lowerBound: SequenceNumber, upperBound: SequenceNumber)
    {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    public init(lowerBound: SequenceNumber, size: UInt16)
    {
        self.lowerBound = lowerBound

        let upperBound = lowerBound.uint32 + UInt32(size)
        if upperBound > UInt32(UInt16.max)
        {
            self.upperBound = SequenceNumber(upperBound - UInt32(UInt16.max))
        }
        else
        {
            self.upperBound = SequenceNumber(upperBound)
        }
    }

    public func increaseUpperBound(by: Int)
    {
        self.increaseUpperBound(by: UInt16(by))
    }

    public func increaseUpperBound(by: UInt16)
    {
        let upperBound = self.upperBound.uint32 + UInt32(by)
        if upperBound > UInt32(UInt16.max)
        {
            self.upperBound = SequenceNumber(upperBound - UInt32(UInt16.max))
        }
        else
        {
            self.upperBound = SequenceNumber(upperBound)
        }
    }
}

extension InternetProtocols.TCP
{
    public var window: SequenceNumberRange
    {
        return SequenceNumberRange(lowerBound: SequenceNumber(self.sequenceNumber), size: self.windowSize)
    }
}
