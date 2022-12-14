//
//  TCPReceiveStraw.swift
//
//
//  Created by Dr. Brandon Wiley on 9/27/22.
//

import Foundation

import Chord
import InternetProtocols
import Straw

public class TCPUpstreamStraw
{
    public var acknowledgementNumber: SequenceNumber
    {
        return AsyncAwaitSynchronizer<SequenceNumber>.sync
        {
            return await self.actor.getAcknowledgementNumber()
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
    }

    let actor: TCPUpstreamStrawActor

    public init(segmentStart: SequenceNumber)
    {
        self.actor = TCPUpstreamStrawActor(segmentStart: segmentStart)
    }

    func inWindow(_ tcp: InternetProtocols.TCP) -> Bool
    {
        let result: Bool = AsyncAwaitSynchronizer<Bool>.sync
        {
            return await self.actor.inWindow(tcp)
        }

        return result
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

    public func clear(segment: SegmentData) throws
    {
        AsyncAwaitThrowingEffectSynchronizer.sync
        {
            return try await self.actor.clear(segment: segment)
        }
    }

}
