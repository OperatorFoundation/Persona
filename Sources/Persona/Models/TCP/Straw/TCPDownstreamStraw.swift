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
    var privateAcknowledgementNumber: SequenceNumber
    var open = true

    // Public constructors
    public init(segmentStart: SequenceNumber, acknowledgementNumber: SequenceNumber, windowSize: UInt16)
    {
        self.window = SequenceNumberRange(lowerBound: segmentStart, size: UInt32(windowSize))
        self.privateAcknowledgementNumber = acknowledgementNumber
        self.privateWindowSize = UInt32(windowSize)
    }

    public func sequenceNumber() async -> SequenceNumber
    {
        return self.window.lowerBound
    }

    public func acknowledgementNumber() async -> SequenceNumber
    {
        return self.privateAcknowledgementNumber
    }

    func inWindow(_ tcp: InternetProtocols.TCP) async -> Bool
    {
        let sequenceNumberData = tcp.sequenceNumber
        let sequenceNumber = SequenceNumber(sequenceNumberData)

        guard self.window.contains(sequenceNumber: sequenceNumber) else
        {
            return false
        }

        if let payload = tcp.payload
        {
            let maxSize = await self.windowSize()
            guard payload.count <= maxSize else
            {
                return false
            }
        }

        return true
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
    public func write(_ segment: InternetProtocols.TCP) async throws
    {
        guard self.open else
        {
            throw TCPUpstreamStrawError.strawClosed
        }

        guard let payload = segment.payload else
        {
            return
        }

        // TODO: Handle out of sequence things
        guard segment.window.lowerBound == self.window.lowerBound else
        {
            throw TCPDownstreamStrawError.misorderedSegment(expected: self.window.lowerBound, actual: segment.window.lowerBound)
        }

        await self.straw.write(payload)
        try self.window.increaseLowerBounds(by: payload.count)
    }

    public func read() async throws -> SegmentData
    {
        let data = try await self.straw.readAllData()
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

public enum TCPDownstreamStrawError: Error
{
    case misorderedSegment(expected: SequenceNumber, actual: SequenceNumber)
}
