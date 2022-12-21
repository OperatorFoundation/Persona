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
        self.functionLock.wait()

        let result = self.window.lowerBound

        self.functionLock.signal()

        return result
    }

    public var windowSize: UInt16
    {
        get
        {
            self.functionLock.wait()

            let result = self.privateWindowSize

            self.functionLock.signal()

            return result
        }

        set
        {
            self.functionLock.wait()

            self.privateWindowSize = newValue

            self.functionLock.signal()
        }
    }

    // Private let properties
    let straw = SynchronizedStraw()
    let functionLock: DispatchSemaphore = DispatchSemaphore(value: 1)
    let countLock: CountingLock = CountingLock()

    // Private var properties
    var window: SequenceNumberRange
    var privateWindowSize: UInt16

    // Public constructors
    public init(segmentStart: SequenceNumber, windowSize: UInt16)
    {
        self.window = SequenceNumberRange(lowerBound: segmentStart, size: windowSize)
        self.privateWindowSize = windowSize
    }

    // Public functions
    public func write(_ data: Data) throws
    {
        self.functionLock.wait()

        self.straw.write(data)
        self.window.increaseUpperBound(by: data.count)
        self.countLock.add(amount: data.count)

        self.functionLock.signal()
    }

    public func read() throws -> SegmentData
    {
        self.countLock.waitFor(amount: 1)

        self.functionLock.wait()

        let data = try self.straw.read()
        self.window.increaseUpperBound(by: data.count)
        let result = SegmentData(data: data, window: window)
        self.countLock.waitFor(amount: data.count - 1)

        self.functionLock.signal()

        return result
    }

    public func read(size: Int) throws -> SegmentData
    {
        self.countLock.waitFor(amount: size)

        self.functionLock.wait()

        let data = try self.straw.read(size: size)
        self.window.increaseUpperBound(by: data.count)
        let result = SegmentData(data: data, window: window)

        self.functionLock.signal()

        return result
    }

    public func read(maxSize: Int) throws -> SegmentData
    {
        self.countLock.waitFor(amount: 1)

        self.functionLock.wait()

        let data = try self.straw.read(maxSize: maxSize)
        self.window.increaseUpperBound(by: data.count)
        let result = SegmentData(data: data, window: window)
        self.countLock.waitFor(amount: data.count - 1)

        self.functionLock.signal()

        return result
    }

    public func clear(acknowledgementNumber: SequenceNumber, sequenceNumber: SequenceNumber) throws
    {
        self.functionLock.wait()

        guard acknowledgementNumber == self.window.lowerBound else
        {
            self.functionLock.signal()
            throw TCPUpstreamStrawError.segmentMismatch
        }

        self.window = SequenceNumberRange(lowerBound: sequenceNumber, upperBound: self.window.upperBound)

        self.functionLock.signal()
    }
}
