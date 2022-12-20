//
//  Latch.swift
//  
//
//  Created by Dr. Brandon Wiley on 12/12/22.
//

import Foundation

public class CountingLock
{
    let functionLock: DispatchSemaphore = DispatchSemaphore(value: 0)
    let countingLock: DispatchSemaphore = DispatchSemaphore(value: 0)

    public init()
    {
    }

    public func add(amount: Int) throws
    {
        functionLock.wait()

        guard amount > 0 else
        {
            functionLock.signal()
            throw CountingLockError.invalidAmount(amount)
        }

        for _ in 0..<amount
        {
            self.countingLock.signal()
        }

        functionLock.signal()
    }

    public func waitFor(amount: Int) throws
    {
        functionLock.wait()

        if amount == 0
        {
            return
        }

        guard amount > 0 else
        {
            functionLock.signal()
            throw CountingLockError.invalidAmount(amount)
        }

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
