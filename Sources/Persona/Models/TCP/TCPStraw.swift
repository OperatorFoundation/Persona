//
//  TCPStraw.swift
//  
//
//  Created by Dr. Brandon Wiley on 9/27/22.
//

import Foundation

import InternetProtocols
import Straw

public actor TCPStraw
{
    let straw = Straw()
    var window: Range<Int>

    public init(segmentStart: Int)
    {
        self.window = segmentStart..<(segmentStart+1)
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
        self.window = self.window.startIndex..<(self.window.endIndex + payload.count)
    }

    public func read() throws -> SegmentData
    {
        let data = try self.straw.read()
        let window = self.window.startIndex..<(self.window.startIndex + data.count)
        return SegmentData(data: data, window: window)
    }

    public func read(size: Int) throws -> SegmentData
    {
        let data = try self.straw.read(size: size)
        let window = self.window.startIndex..<(self.window.startIndex + data.count)
        return SegmentData(data: data, window: window)
    }

    public func read(maxSize: Int) throws -> SegmentData
    {
        let data = try self.straw.read(maxSize: maxSize)
        let window = self.window.startIndex..<(self.window.startIndex + data.count)
        return SegmentData(data: data, window: window)
    }

    public func clear(segment: SegmentData) throws
    {
        guard segment.window.startIndex == self.window.startIndex else
        {
            throw TCPStrawError.segmentMismatch
        }

        self.window = (segment.window.endIndex)..<self.window.endIndex
    }
}

public struct SegmentData
{
    let data: Data
    let window: Range<Int>

    public init(data: Data, window: Range<Int>)
    {
        self.data = data
        self.window = window
    }
}

public extension InternetProtocols.TCP
{
    var segmentWindow: Range<Int>?
    {
        guard let payload = self.payload else
        {
            return nil
        }

        guard let sequenceNumber32 = self.sequenceNumber.maybeNetworkUint32 else
        {
            return nil
        }

        let sequenceNumber = Int(sequenceNumber32)

        return sequenceNumber..<(sequenceNumber+payload.count)
    }
}

public enum TCPStrawError: Error
{
    case unimplemented
    case badSegmentWindow
    case misorderedSegment
    case segmentMismatch
}
