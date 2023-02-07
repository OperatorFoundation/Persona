//
//  Latch.swift
//  
//
//  Created by Dr. Brandon Wiley on 12/12/22.
//

import Foundation

public class CountingLock
{
    let countingLock: DispatchSemaphore = DispatchSemaphore(value: 0)

    public init()
    {
    }

    public func add(amount: Int)
    {
        guard amount > 0 else
        {
            return
        }

        for _ in 0..<amount
        {
            self.countingLock.signal()
        }
    }

    public func add(amount: UInt16)
    {
        guard amount > 0 else
        {
            return
        }

        for _ in 0..<amount
        {
            self.countingLock.signal()
        }
    }

    public func waitFor(amount: Int)
    {
        guard amount > 0 else
        {
            return
        }

        for _ in 0..<amount
        {
            self.countingLock.wait()
        }
    }
}

public enum CountingLockError: Error
{
    case invalidAmount(Int)
}
