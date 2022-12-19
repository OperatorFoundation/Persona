//
//  TCPReceiveStrawActor.swift
//  
//
//  Created by Dr. Brandon Wiley on 9/27/22.
//

import Foundation

import InternetProtocols
import Straw

public class TCPUpstreamStraw
{
    static let maxBufferSize: UInt16 = UInt16.max

    public var acknowledgementNumber: SequenceNumber
    {
        self.functionLock.wait()

        let result = self.window.lowerBound

        self.functionLock.signal()

        return result
    }

    public var windowSize: UInt16
    {
        self.functionLock.wait()

        let result = self.privateWindowSize

        self.functionLock.signal()

        return result
    }

    var privateWindowSize: UInt16
    {
        return Self.maxBufferSize - UInt16(self.straw.count)
    }

    let straw = SynchronizedStraw()
    var window: SequenceNumberRange

    let functionLock: DispatchSemaphore = DispatchSemaphore(value: 0)
    let ackLock: CountingLock = CountingLock()

    public init(segmentStart: SequenceNumber)
    {
        self.window = SequenceNumberRange(lowerBound: segmentStart, size: Self.maxBufferSize)
    }

    func inWindow(_ tcp: InternetProtocols.TCP) -> Bool
    {
        self.functionLock.wait()

        guard SequenceNumber(tcp.sequenceNumber) == self.window.upperBound else
        {
            self.functionLock.signal()
            return false
        }

        if let payload = tcp.payload
        {
            guard payload.count <= self.privateWindowSize else
            {
                self.functionLock.signal()
                return false
            }
        }

        self.functionLock.signal()
        return true
    }

    public func write(_ segment: InternetProtocols.TCP) throws
    {
        self.functionLock.wait()

        guard let payload = segment.payload else
        {
            self.functionLock.signal()
            return
        }

        let segmentWindow = segment.window
        guard segmentWindow.lowerBound == SequenceNumber(segmentWindow.lowerBound.uint32 + UInt32(self.straw.count)) else
        {
            self.functionLock.signal()
            throw TCPUpstreamStrawError.misorderedSegment
        }

        self.straw.write(payload)
        self.window.increaseUpperBound(by: payload.count)

        self.functionLock.signal()
    }

    public func read() throws -> SegmentData
    {
        self.functionLock.wait()

        let data = try self.straw.read()
        self.window.increaseUpperBound(by: data.count)
        let result = SegmentData(data: data, window: window)

        self.functionLock.signal()

        return result
    }

    public func read(size: Int) throws -> SegmentData
    {
        self.functionLock.wait()

        let data = try self.straw.read(size: size)
        self.window.increaseUpperBound(by: data.count)
        let result = SegmentData(data: data, window: window)

        self.functionLock.signal()

        return result
    }

    public func read(maxSize: Int) throws -> SegmentData
    {
        self.functionLock.wait()

        let data = try self.straw.read(maxSize: maxSize)
        self.window.increaseUpperBound(by: data.count)
        let result = SegmentData(data: data, window: window)

        self.functionLock.signal()

        return result
    }

    public func clear(segment: SegmentData) throws
    {
        self.functionLock.wait()

        guard segment.window.lowerBound == self.window.lowerBound else
        {
            self.functionLock.signal()
            throw TCPUpstreamStrawError.segmentMismatch
        }

        self.functionLock.signal()
        self.window = SequenceNumberRange(lowerBound: segment.window.upperBound, upperBound: self.window.upperBound)
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
