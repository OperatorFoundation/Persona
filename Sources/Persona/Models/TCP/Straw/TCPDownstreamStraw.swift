//
//  TCPSendStrawActor.swift
//
//
//  Created by Dr. Brandon Wiley on 9/27/22.
//

import Foundation

import InternetProtocols
import Straw

public class TCPDownstreamStraw
{
    // Public computed properties
    public var sequenceNumber: SequenceNumber
    {
        defer
        {
            self.functionLock.signal()
        }
        self.functionLock.wait()

        let result = self.window.lowerBound

        return result
    }
    
    public var isEmpty: Bool
    {
        defer
        {
            self.functionLock.signal()
        }
        self.functionLock.wait()

        return self.window.upperBound == self.window.lowerBound
    }

    public var windowSize: UInt16
    {
        get
        {
            defer
            {
                self.functionLock.signal()
            }
            self.functionLock.wait()

            let result = self.privateWindowSize

            return UInt16(result)
        }

        set
        {
            defer
            {
                self.functionLock.signal()
            }
            self.functionLock.wait()

            self.privateWindowSize = UInt32(newValue)
        }
    }

    // Private let properties
    let straw = SynchronizedStraw()
    let functionLock: DispatchSemaphore = DispatchSemaphore(value: 1)
    let countLock: CountingLock = CountingLock()

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
    public func write(_ data: Data) throws
    {
        defer
        {
            self.functionLock.signal()
        }
        self.functionLock.wait()

        self.straw.write(data)
        // FIXME: Figure out how to adjust the bounds correctly
//        try self.window.increaseBounds(by: data.count)
        self.countLock.add(amount: data.count)
    }

    public func read() throws -> SegmentData
    {
        self.countLock.waitFor(amount: 1)

        defer
        {
            self.functionLock.signal()
        }
        self.functionLock.wait()

        let data = try self.straw.read()
        // FIXME: Figure out how to adjust the bounds correctly
//        try self.window.increaseBounds(by: data.count)
        let result = SegmentData(data: data, window: window)
        self.countLock.waitFor(amount: data.count - 1)

        return result
    }

    public func read(size: Int) throws -> SegmentData
    {
        self.countLock.waitFor(amount: size)

        defer
        {
            self.functionLock.signal()
        }
        self.functionLock.wait()

        let data = try self.straw.read(size: size)
        // FIXME: Figure out how to adjust the bounds correctly
//        try self.window.increaseBounds(by: data.count)
        let result = SegmentData(data: data, window: window)

        return result
    }

    public func read(maxSize: Int) throws -> SegmentData
    {
        self.countLock.waitFor(amount: 1)

        defer
        {
            self.functionLock.signal()
        }
        self.functionLock.wait()

        let data = try self.straw.read(maxSize: maxSize)
        // FIXME: Figure out how to adjust the bounds correctly
//        try self.window.increaseBounds(by: data.count)
        let result = SegmentData(data: data, window: window)
        self.countLock.waitFor(amount: data.count - 1)

        return result
    }

    public func clear(bytesSent: Int) throws
    {
        defer
        {
            self.functionLock.signal()
        }
        self.functionLock.wait()
        
        let newLowerBound = self.window.lowerBound.add(bytesSent)
        self.window = SequenceNumberRange(lowerBound: newLowerBound, upperBound: self.window.upperBound)
    }
}
