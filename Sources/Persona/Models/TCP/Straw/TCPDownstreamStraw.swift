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

    public func sequenceNumber() async -> SequenceNumber
    {
        return self.window.lowerBound
    }

    public func isEmpty() -> Bool
    {
        return self.window.upperBound == self.window.lowerBound
    }

    public func windowSize() async -> UInt16
    {
        let result = self.privateWindowSize

        return UInt16(result)
    }

    public func setWindowSize(newValue: UInt16) async
    {
        self.privateWindowSize = UInt32(newValue)
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
