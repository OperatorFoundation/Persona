//
//  LatchingLock.swift
//  
//
//  Created by Dr. Brandon Wiley on 12/12/22.
//

import Foundation

import Chord

public class LatchingLock
{
    let actor = LatchingLockActor()

    public init()
    {
    }

    public func latch()
    {
        AsyncAwaitEffectSynchronizer.sync
        {
            await self.actor.latch()
        }
    }

    public func wait()
    {
        AsyncAwaitEffectSynchronizer.sync
        {
            await self.actor.wait()
        }
    }
}
