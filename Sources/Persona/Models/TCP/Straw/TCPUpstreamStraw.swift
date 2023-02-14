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

public class TCPUpstreamStraw
{
    // static private properties
    static let maxBufferSize: UInt32 = UInt32(UInt16.max)

    // public computed properties
    public var acknowledgementNumber: SequenceNumber
    {
        self.functionLock.wait()

        let result = self.window.lowerBound
        self.lastAck = result
        self.privateAckUpdated = false

        self.functionLock.signal()

        return result
    }

    public var windowSize: UInt16
    {
        self.functionLock.wait()

        let result = self.privateWindowSize

        self.functionLock.signal()

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
    let functionLock: DispatchSemaphore = DispatchSemaphore(value: 1)
    let readLock: CountingLock = CountingLock()

    // private var properties
    var lastAck: SequenceNumber? = nil
    var window: SequenceNumberRange
    var privateAckUpdated = false
    var open = true

    // public constructors
    public init(segmentStart: SequenceNumber)
    {
        print(" ^ Creating window, segment start - \(segmentStart)")
        self.window = SequenceNumberRange(lowerBound: segmentStart, size: Self.maxBufferSize)
    }

    // public functions
    func inWindow(_ tcp: InternetProtocols.TCP) -> Bool
    {
        self.functionLock.wait()
        
        let sequenceNumberData = tcp.sequenceNumber
        let sequenceNumber = SequenceNumber(sequenceNumberData)
        
        print(" ^ inWindow sequenceNumber - \(sequenceNumber)")
        print(" ^ inWindow lowerBound - \(self.window.lowerBound)")
        print(" ^ inWindow upperBound - \(self.window.upperBound)")
        print(" ^ inWindow privateWindowSize \(privateWindowSize)")
        
        
        guard self.window.contains(sequenceNumber: sequenceNumber) else
        {
            self.functionLock.signal()
            print(" ^ inWindow sequence number is not in the expected window")
            return false
        }

        if let payload = tcp.payload
        {
            print(" ^ inWindow payload.count - \(payload.count)")
            guard payload.count <= self.privateWindowSize else
            {
                print(" ^ inWindow Payload is too large - \(payload.count)")
                self.functionLock.signal()
                return false
            }
        }

        self.functionLock.signal()
        return true
    }

    public func write(_ segment: InternetProtocols.TCP) throws
    {
        defer
        {
            self.functionLock.signal()
        }
        self.functionLock.wait()
        
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
        self.readLock.add(amount: payload.count)
    }

    public func read() throws -> SegmentData
    {
        self.readLock.waitFor(amount: 1) // We need at least 1 byte.

        defer
        {
            self.functionLock.signal()
        }
        self.functionLock.wait()

        let data = try self.straw.read()
        let result = SegmentData(data: data, window: window)
        self.readLock.waitFor(amount: data.count - 1) // We already waited for the first byte, decrement the counter for the rest of the bytes.

        return result
    }

    public func read(size: Int) throws -> SegmentData
    {
        guard size > 0 else
        {
            throw TCPUpstreamStrawError.badReadSize(size)
        }

        self.readLock.waitFor(amount: size)

        defer
        {
            self.functionLock.signal()
        }
        self.functionLock.wait()

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

        self.readLock.waitFor(amount: 1) // We need at least 1 byte.

        defer
        {
            self.functionLock.signal()
        }
        self.functionLock.wait()

        let data = try self.straw.read(maxSize: maxSize)
        let result = SegmentData(data: data, window: window)
        self.readLock.waitFor(amount: data.count - 1) // We already waited for the first byte, decrement the counter for the rest of the bytes.

        return result
    }

    public func clear(segment: SegmentData) throws
    {
        guard segment.window.size > 0 else
        {
            throw TCPUpstreamStrawError.badClearSize(segment.window.size)
        }

        defer
        {
            self.functionLock.signal()
        }
        self.functionLock.wait()

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
