//
//  TCPSendStrawActor.swift
//
//
//  Created by Dr. Brandon Wiley on 9/27/22.
//

import Foundation

import InternetProtocols
import Straw

public actor TCPDownstreamStraw
{
    // Public computed properties
    public var sequenceNumber: SequenceNumber
    {
        let result = self.window.lowerBound

        return result
    }
    
    public var isEmpty: Bool
    {
        return self.window.upperBound == self.window.lowerBound
    }

    public var windowSize: UInt16
    {
        get
        {
            let result = self.privateWindowSize

            return UInt16(result)
        }

        set
        {
            self.privateWindowSize = UInt32(newValue)
        }
    }

    // Private let properties
    let straw = StrawActor()

    // Private var properties
    var window: SequenceNumberRange
    var privateWindowSize: UInt32

    // Public constructors
    public init(segmentStart: SequenceNumber, windowSize: UInt16)
    {
        self.window = SequenceNumberRange(lowerBound: segmentStart.increment(), size: UInt32(windowSize))
        self.privateWindowSize = UInt32(windowSize)
    }

    // Public functions
    public func write(_ data: Data) async throws
    {
        await self.straw.write(data)
        // FIXME: Figure out how to adjust the bounds correctly
//        try self.window.increaseBounds(by: data.count)
    }

    public func read() async throws -> SegmentData
    {
        let data = try await self.straw.read()
        // FIXME: Figure out how to adjust the bounds correctly
//        try self.window.increaseBounds(by: data.count)
        let result = SegmentData(data: data, window: window)

        return result
    }

    public func read(size: Int) async throws -> SegmentData
    {
        let data = try await self.straw.read(size: size)
        // FIXME: Figure out how to adjust the bounds correctly
//        try self.window.increaseBounds(by: data.count)
        let result = SegmentData(data: data, window: window)

        return result
    }

    public func read(maxSize: Int) async throws -> SegmentData
    {
        let data = try await self.straw.read(maxSize: maxSize)
        // FIXME: Figure out how to adjust the bounds correctly
//        try self.window.increaseBounds(by: data.count)
        let result = SegmentData(data: data, window: window)

        return result
    }

    public func clear(bytesSent: Int) throws
    {
        let newLowerBound = self.window.lowerBound.add(bytesSent)
        self.window = SequenceNumberRange(lowerBound: newLowerBound, upperBound: self.window.upperBound)
    }
}
