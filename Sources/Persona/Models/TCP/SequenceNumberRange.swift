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

    public var size: UInt32
    {
        if lowerBound < upperBound
        {
            return upperBound.uint32 - lowerBound.uint32
        }
        else
        {
            // If the upper bound has exceeded UInt32.max, it will wrap around to 0.
            // In this case, the lower bound will be larger than the upper bound.
            // Allow for this by taking the difference between max and lower bound, and adding the upper bound
            // to get the correct size after an upper bound wrap.
            return ((UInt32.max - lowerBound.uint32) + upperBound.uint32)
        }
    }

    public init(lowerBound: SequenceNumber, upperBound: SequenceNumber)
    {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    public init(lowerBound: SequenceNumber, size: UInt32)
    {
        self.lowerBound = lowerBound

        let maxSize = UInt32.max - lowerBound.uint32
        
        if size > maxSize
        {
            // Overflow
            self.upperBound = SequenceNumber(size - maxSize)
        }
        else
        {
            self.upperBound = SequenceNumber(lowerBound.uint32 + size)
        }
    }
    
    public func increaseUpperBounds(by increaseAmount: Int) throws
    {
        guard (increaseAmount <= UInt16.max) else
        {
            throw SequenceNumberError.outOfBounds(badNumber: increaseAmount)
        }
        
        let increaseAmountUInt32 = UInt32(increaseAmount)
        
        // Overflow state?
        if lowerBound.uint32 < upperBound.uint32
        {
            // Normal State
            
            // Will adding the new amount put us in an overflow state?
            if UInt32.max - upperBound.uint32 > increaseAmountUInt32
            {
                // Nah
                upperBound = upperBound.add(increaseAmount)
            }
            else
            {
                // Yes
                upperBound = SequenceNumber(increaseAmountUInt32 - (UInt32.max - upperBound.uint32))
            }
        }
        else
        {
            // Overflow State
            upperBound = upperBound.add(increaseAmount)
        }
    }
    
    public func increaseLowerBounds(by increaseAmount: Int) throws
    {
        guard (increaseAmount <= UInt16.max) else
        {
            throw SequenceNumberError.outOfBounds(badNumber: increaseAmount)
        }
        
        let increaseAmountUInt32 = UInt32(increaseAmount)
        
        // Overflow state?
        if lowerBound.uint32 < upperBound.uint32
        {
            // Normal State
            lowerBound = lowerBound.add(increaseAmount)
        }
        else
        {
            // Overflow State
            
            // Will adding the new amount put us out of the overflow state?
            if UInt32.max - lowerBound.uint32 > increaseAmountUInt32
            {
                // Yes
                lowerBound = SequenceNumber(increaseAmountUInt32 - (UInt32.max - lowerBound.uint32))
            }
            else
            {
                // Nope
                lowerBound = lowerBound.add(increaseAmount)
            }
        }
    }
    
    public func contains(sequenceNumber: SequenceNumber) -> Bool
    {
        if lowerBound.uint32 < upperBound.uint32
        {
            return (sequenceNumber >= lowerBound && sequenceNumber <= upperBound)
        }
        else
        {
            // Overflow case
            return (sequenceNumber >= upperBound || sequenceNumber <= lowerBound)
        }
    }
}

extension InternetProtocols.TCP
{
    public var window: SequenceNumberRange
    {
        return SequenceNumberRange(lowerBound: SequenceNumber(self.sequenceNumber), size: UInt32(self.windowSize))
    }
}

public enum SequenceNumberError: Error
{
    case outOfBounds(badNumber: Int)
}
