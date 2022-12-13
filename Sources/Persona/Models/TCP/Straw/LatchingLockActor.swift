//
//  Latch.swift
//  
//
//  Created by Dr. Brandon Wiley on 12/12/22.
//

import Foundation

public actor LatchingLockActor
{
    var latched: Bool = true
    let lock: DispatchSemaphore = DispatchSemaphore(value: 0)

    public init()
    {
    }

    public func latch()
    {
        if latched
        {
            // No need to latch
            return
        }
        else
        {
            // Latch
            latched = true
            self.lock.signal()
        }
    }

    public func wait()
    {
        if latched
        {
            // Unlatch
            self.lock.wait()
            latched = false
        }
        else
        {
            // No need to unlatch
            return
        }
    }
}
