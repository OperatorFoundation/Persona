//
//  Latch.swift
//  
//
//  Created by Dr. Brandon Wiley on 12/12/22.
//

import Foundation

public class CountingLock
{
    let functionLock: DispatchSemaphore = DispatchSemaphore(value: 1)
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

        functionLock.wait()

        for _ in 0..<amount
        {
            self.countingLock.signal()
        }

        functionLock.signal()
    }

    public func add(amount: UInt16)
    {
        guard amount > 0 else
        {
            return
        }

        functionLock.wait()

        for _ in 0..<amount
        {
            self.countingLock.signal()
        }

        functionLock.signal()
    }

    public func waitFor(amount: Int)
    {
        guard amount > 0 else
        {
            return
        }

        functionLock.wait()

        for _ in 0..<amount
        {
            self.countingLock.wait()
        }

        functionLock.signal()
    }
}

public enum CountingLockError: Error
{
    case invalidAmount(Int)
}
