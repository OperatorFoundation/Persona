//
//  TCPReceiveStrawActor.swift
//  
//
//  Created by Dr. Brandon Wiley on 9/27/22.
//

import Foundation

import InternetProtocols
import Straw

// FIXME - add periodic acks if there is no data to send downstream

public actor TCPUpstreamStraw
{
    // static private properties
    static let maxBufferSize: UInt32 = UInt32(UInt16.max)

    // public computed properties
    public var acknowledgementNumber: SequenceNumber
    {
        let result = self.window.lowerBound
        self.lastAck = result
        self.privateAckUpdated = false

        return result
    }

    public var windowSize: UInt16
    {
        let result = self.privateWindowSize

        return UInt16(result)
    }

    public var ackUpdated: Bool
    {
        return self.privateAckUpdated
    }

    // private computed properties
    var privateWindowSize: UInt32
    {
        return Self.maxBufferSize - UInt32(self.straw.count)
    }

    // private let properties
    let straw = SynchronizedStraw()

    // private var properties
    var lastAck: SequenceNumber? = nil
    var window: SequenceNumberRange
    var privateAckUpdated = false
    var open = true

    // public constructors
    public init(segmentStart: SequenceNumber)
    {
        self.window = SequenceNumberRange(lowerBound: segmentStart, size: Self.maxBufferSize)
    }

    // public functions
    func inWindow(_ tcp: InternetProtocols.TCP) -> Bool
    {
        let sequenceNumberData = tcp.sequenceNumber
        let sequenceNumber = SequenceNumber(sequenceNumberData)
        
        guard self.window.contains(sequenceNumber: sequenceNumber) else
        {
            return false
        }

        if let payload = tcp.payload
        {
            guard payload.count <= self.privateWindowSize else
            {
                return false
            }
        }

        return true
    }

    public func write(_ segment: InternetProtocols.TCP) throws
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
            throw TCPUpstreamStrawError.misorderedSegment
        }

        self.straw.write(payload)
        try self.window.increaseLowerBounds(by: payload.count)
    }

    public func read() throws -> SegmentData
    {
        let data = try self.straw.read()
        let result = SegmentData(data: data, window: window)

        return result
    }

    public func read(size: Int) throws -> SegmentData
    {
        guard size > 0 else
        {
            throw TCPUpstreamStrawError.badReadSize(size)
        }

        let data = try self.straw.read(size: size)
        let result = SegmentData(data: data, window: window)

        return result
    }

    public func read(maxSize: Int) throws -> SegmentData
    {
        guard maxSize > 0 else
        {
            throw TCPUpstreamStrawError.badReadSize(maxSize)
        }

        let data = try self.straw.read(maxSize: maxSize)
        let result = SegmentData(data: data, window: window)

        return result
    }

    public func clear(segment: SegmentData) throws
    {
        guard segment.window.size > 0 else
        {
            throw TCPUpstreamStrawError.badClearSize(segment.window.size)
        }

        guard segment.window.lowerBound == self.window.lowerBound else
        {
            throw TCPUpstreamStrawError.segmentMismatch
        }

        try self.window.increaseUpperBounds(by: segment.data.count)
        self.privateAckUpdated = true
    }
    
    public func close()
    {
        let newWindow = SequenceNumberRange(lowerBound: self.window.lowerBound.add(1), upperBound: self.window.upperBound)
        self.window = newWindow
        self.open = false
    }
}

// public helpers structs
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

// public error enum
public enum TCPUpstreamStrawError: Error
{
    case unimplemented
    case badSegmentWindow
    case misorderedSegment
    case segmentMismatch
    case strawClosed
    case badReadSize(Int)
    case badClearSize(UInt32)
}
