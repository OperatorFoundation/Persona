//
//  TCPSendStraw.swift
//
//
//  Created by Dr. Brandon Wiley on 9/27/22.
//

import Foundation

import Chord
import InternetProtocols
import Straw

public class TCPDownstreamStraw
{
    public var sequenceNumber: SequenceNumber
    {
        return AsyncAwaitSynchronizer<SequenceNumber>.sync
        {
            return await self.actor.getSequenceNumber()
        }
    }

    public var windowSize: UInt16
    {
        get
        {
            return AsyncAwaitSynchronizer<UInt16>.sync
            {
                return await self.actor.getWindowSize()
            }
        }

        set
        {
            AsyncAwaitEffectSynchronizer.sync
            {
                await self.actor.updateWindowSize(newValue)
            }
        }
    }

    let actor: TCPDownstreamStrawActor

    public init(segmentStart: SequenceNumber, windowSize: UInt16)
    {
        self.actor = TCPDownstreamStrawActor(segmentStart: segmentStart, windowSize: windowSize)
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
        let result: SegmentData = try AsyncAwaitThrowingSynchronizer<SegmentData>.sync
        {
            return try await self.actor.read()
        }

        return result
    }

    public func read(size: Int) throws -> SegmentData
    {
        let result: SegmentData = try AsyncAwaitThrowingSynchronizer<SegmentData>.sync
        {
            return try await self.actor.read(size: size)
        }

        return result
    }

    public func read(maxSize: Int) throws -> SegmentData
    {
        let result: SegmentData = try AsyncAwaitThrowingSynchronizer<SegmentData>.sync
        {
            return try await self.actor.read(maxSize: maxSize)
        }

        return result
    }

    public func clear(tcp: InternetProtocols.TCP) throws
    {
        AsyncAwaitThrowingEffectSynchronizer.sync
        {
            return try await self.actor.clear(tcp: tcp)
        }
    }
}
