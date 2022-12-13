//
//  TCPReceiveStraw.swift
//  
//
//  Created by Dr. Brandon Wiley on 12/12/22.
//

import Foundation

import Chord
import InternetProtocols
import Straw

public class TCPReceiveStraw
{
    let actor: TCPReceiveStrawActor

    public init(segmentStart: UInt32)
    {
        self.actor = TCPReceiveStrawActor(segmentStart: segmentStart)
    }

    public func write(_ segment: InternetProtocols.TCP) throws
    {
        AsyncAwaitThrowingEffectSynchronizer.sync
        {
            try await self.actor.write(segment)
        }
    }

    public func read() throws -> SegmentData
    {
        return try AsyncAwaitThrowingSynchronizer<SegmentData>.sync
        {
            return try await self.actor.read()
        }
    }

    public func read(size: Int) throws -> SegmentData
    {
        return try AsyncAwaitThrowingSynchronizer<SegmentData>.sync
        {
            return try await self.actor.read(size: size)
        }
    }

    public func read(maxSize: Int) throws -> SegmentData
    {
        return try AsyncAwaitThrowingSynchronizer<SegmentData>.sync
        {
            return try await self.actor.read(maxSize: maxSize)
        }
    }

    public func clear(segment: SegmentData)
    {
        AsyncAwaitThrowingEffectSynchronizer.sync
        {
            try await self.actor.clear(segment: segment)
        }
    }

    public func getAcknowledgementNumber() -> SequenceNumber
    {
        return AsyncAwaitSynchronizer<SequenceNumber>.sync
        {
            return await self.actor.getAcknowledgementNumber()
        }
    }
}
