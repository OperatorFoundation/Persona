//
//  TCPReceiveStrawActor.swift
//  
//
//  Created by Dr. Brandon Wiley on 9/27/22.
//

import Foundation

import InternetProtocols
import Straw

public actor TCPUpstreamStrawActor
{
    static let maxBufferSize: UInt16 = UInt16.max

    let straw = SynchronizedStraw()
    var window: SequenceNumberRange
    let ackLock: LatchingLock = LatchingLock()

    public init(segmentStart: SequenceNumber)
    {
        self.window = SequenceNumberRange(lowerBound: segmentStart, size: Self.maxBufferSize)
    }

    public func getAcknowledgementNumber() -> SequenceNumber
    {
        //self.ackLock.wait()

        return self.window.lowerBound
    }

    public func getWindowSize() -> UInt16
    {
        return Self.maxBufferSize - UInt16(self.straw.count)
    }

    func inWindow(_ tcp: InternetProtocols.TCP) -> Bool
    {
        guard SequenceNumber(tcp.sequenceNumber) == self.window.upperBound else
        {
            return false
        }

        if let payload = tcp.payload
        {
            guard payload.count <= self.getWindowSize() else
            {
                return false
            }
        }

        return true
    }

    public func write(_ segment: InternetProtocols.TCP) throws
    {
        guard let payload = segment.payload else
        {
            return
        }

        let segmentWindow = segment.window
        guard segmentWindow.lowerBound == SequenceNumber(segmentWindow.lowerBound.uint32 + UInt32(self.straw.count)) else
        {
            throw TCPUpstreamStrawError.misorderedSegment
        }

        self.straw.write(payload)
        self.window.increaseUpperBound(by: payload.count)
    }

    public func read() throws -> SegmentData
    {
        let data = try self.straw.read()
        self.window.increaseUpperBound(by: data.count)
        return SegmentData(data: data, window: window)
    }

    public func read(size: Int) throws -> SegmentData
    {
        let data = try self.straw.read(size: size)
        self.window.increaseUpperBound(by: data.count)
        return SegmentData(data: data, window: window)
    }

    public func read(maxSize: Int) throws -> SegmentData
    {
        let data = try self.straw.read(maxSize: maxSize)
        self.window.increaseUpperBound(by: data.count)
        return SegmentData(data: data, window: window)
    }

    public func clear(segment: SegmentData) throws
    {
        guard segment.window.lowerBound == self.window.lowerBound else
        {
            throw TCPUpstreamStrawError.segmentMismatch
        }

        self.window = SequenceNumberRange(lowerBound: segment.window.upperBound, upperBound: self.window.upperBound)

        self.ackLock.latch()
    }
}

public struct SegmentData
{
    let data: Data
    let window: SequenceNumberRange

    public init(data: Data, window: SequenceNumberRange)
    {
        self.data = data
        self.window = window
    }
}

public enum TCPUpstreamStrawError: Error
{
    case unimplemented
    case badSegmentWindow
    case misorderedSegment
    case segmentMismatch
}
