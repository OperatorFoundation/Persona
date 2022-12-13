//
//  TCPReceiveStraw.swift
//  
//
//  Created by Dr. Brandon Wiley on 9/27/22.
//

import Foundation

import InternetProtocols
import Straw

public actor TCPUpstreamStraw
{
    static let maxBufferSize: UInt16 = UInt16.max

    let straw = SynchronizedStraw()
    var window: Range<UInt32>
    let ackLock: LatchingLock = LatchingLock()

    public init(segmentStart: UInt32)
    {
        self.window = segmentStart..<(segmentStart+1)
    }

    public func getAcknowledgementNumber() -> SequenceNumber
    {
        self.ackLock.wait()

        return SequenceNumber(self.window.startIndex)
    }

    public func getWindowSize() -> UInt16
    {
        return Self.maxBufferSize - UInt16(self.straw.count)
    }

    func inWindow(_ tcp: InternetProtocols.TCP) -> Bool
    {
        guard SequenceNumber(tcp.sequenceNumber) == SequenceNumber(self.window.upperBound) else
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

        guard let segmentWindow = segment.segmentWindow else
        {
            throw TCPStrawError.badSegmentWindow
        }

        guard segmentWindow.startIndex == self.window.endIndex else
        {
            throw TCPStrawError.misorderedSegment
        }

        self.straw.write(payload)
        self.window = self.window.startIndex..<(self.window.endIndex + UInt32(payload.count))
    }

    public func read() throws -> SegmentData
    {
        let data = try self.straw.read()
        let window = self.window.startIndex..<(self.window.startIndex + UInt32(data.count))
        return SegmentData(data: data, window: window)
    }

    public func read(size: Int) throws -> SegmentData
    {
        let data = try self.straw.read(size: size)
        let window = self.window.startIndex..<(self.window.startIndex + UInt32(data.count))
        return SegmentData(data: data, window: window)
    }

    public func read(maxSize: Int) throws -> SegmentData
    {
        let data = try self.straw.read(maxSize: maxSize)
        let window = self.window.startIndex..<(self.window.startIndex + UInt32(data.count))
        return SegmentData(data: data, window: window)
    }

    public func clear(segment: SegmentData) throws
    {
        guard segment.window.startIndex == self.window.startIndex else
        {
            throw TCPStrawError.segmentMismatch
        }

        self.window = (segment.window.endIndex)..<self.window.endIndex

        self.ackLock.latch()
    }
}

public struct SegmentData
{
    let data: Data
    let window: Range<UInt32>

    public init(data: Data, window: Range<UInt32>)
    {
        self.data = data
        self.window = window
    }
}

public extension InternetProtocols.TCP
{
    var segmentWindow: Range<UInt32>?
    {
        guard let payload = self.payload else
        {
            return nil
        }

        guard let sequenceNumber32 = self.sequenceNumber.maybeNetworkUint32 else
        {
            return nil
        }

        return sequenceNumber32..<(sequenceNumber32+UInt32(exactly: payload.count)!)
    }
}

public enum TCPStrawError: Error
{
    case unimplemented
    case badSegmentWindow
    case misorderedSegment
    case segmentMismatch
}
