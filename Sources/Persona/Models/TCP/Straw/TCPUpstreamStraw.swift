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
    static let maxBufferSize: UInt16 = UInt16.max

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

        return result
    }

    public var ackUpdated: Bool
    {
        return self.privateAckUpdated
    }

    // private computed properties
    var privateWindowSize: UInt16
    {
        return Self.maxBufferSize - UInt16(self.straw.count)
    }

    // private let properties
    let straw = SynchronizedStraw()
    let functionLock: DispatchSemaphore = DispatchSemaphore(value: 1)
    let readLock: CountingLock = CountingLock()

    // private var properties
    var lastAck: SequenceNumber? = nil
    var window: SequenceNumberRange
    var privateAckUpdated = false

    // public constructors
    public init(segmentStart: SequenceNumber)
    {
        self.window = SequenceNumberRange(lowerBound: segmentStart, size: Self.maxBufferSize)
    }

    // public functions
    func inWindow(_ tcp: InternetProtocols.TCP) -> Bool
    {
        self.functionLock.wait()
        
        let sequenceNumberData = tcp.sequenceNumber
        let sequenceNumber = SequenceNumber(sequenceNumberData)
        
        print(" ^ inWindow sequenceNumber - \(sequenceNumber)")
        print(" ^ inWindow upperBound - \(self.window.upperBound)")
        print(" ^ inWindow privateWindowSize \(privateWindowSize)")
        
        
        guard sequenceNumber == self.window.upperBound else
        {
            self.functionLock.signal()
            print(" ^ inWindow upperBound and sequence number do not match")
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
        self.readLock.add(amount: payload.count)

        self.functionLock.signal()
    }

    public func read() throws -> SegmentData
    {
        self.readLock.waitFor(amount: 1) // We need at least 1 byte.

        self.functionLock.wait()

        let data = try self.straw.read()
        self.window.increaseUpperBound(by: data.count)
        let result = SegmentData(data: data, window: window)
        self.readLock.waitFor(amount: data.count - 1) // We already waited for the first byte, decrement the counter for the rest of the bytes.

        self.functionLock.signal()

        return result
    }

    public func read(size: Int) throws -> SegmentData
    {
        guard size > 0 else
        {
            throw TCPUpstreamStrawError.badReadSize(size)
        }

        self.readLock.waitFor(amount: size)

        self.functionLock.wait()

        let data = try self.straw.read(size: size)
        self.window.increaseUpperBound(by: data.count)
        let result = SegmentData(data: data, window: window)

        self.functionLock.signal()

        return result
    }

    public func read(maxSize: Int) throws -> SegmentData
    {
        guard maxSize > 0 else
        {
            throw TCPUpstreamStrawError.badReadSize(maxSize)
        }

        self.readLock.waitFor(amount: 1) // We need at least 1 byte.

        self.functionLock.wait()

        let data = try self.straw.read(maxSize: maxSize)
        self.window.increaseUpperBound(by: data.count)
        let result = SegmentData(data: data, window: window)
        self.readLock.waitFor(amount: data.count - 1) // We already waited for the first byte, decrement the counter for the rest of the bytes.

        self.functionLock.signal()

        return result
    }

    public func clear(segment: SegmentData) throws
    {
        guard segment.window.size > 0 else
        {
            throw TCPUpstreamStrawError.badClearSize(segment.window.size)
        }

        self.functionLock.wait()

        guard segment.window.lowerBound == self.window.lowerBound else
        {
            self.functionLock.signal()
            throw TCPUpstreamStrawError.segmentMismatch
        }

        self.window = SequenceNumberRange(lowerBound: segment.window.upperBound, upperBound: self.window.upperBound)
        self.privateAckUpdated = true

        self.functionLock.signal()
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
    case badReadSize(Int)
    case badClearSize(UInt16)
}
