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
    let straw = SynchronizedStraw()
    var window: SequenceNumberRange
    var privateWindowSize: UInt16

    let functionLock: DispatchSemaphore = DispatchSemaphore(value: 0)
    let countLock: CountingLock = CountingLock()

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

    public init(segmentStart: SequenceNumber, windowSize: UInt16)
    {
        self.window = SequenceNumberRange(lowerBound: segmentStart, size: windowSize)
        self.privateWindowSize = windowSize
    }

    public func write(_ data: Data) throws
    {
        self.functionLock.wait()

        self.straw.write(data)
        self.window.increaseUpperBound(by: data.count)
        try self.countLock.add(amount: data.count)

        self.functionLock.signal()
    }

    public func read() throws -> SegmentData
    {
        self.functionLock.wait()

        try self.countLock.waitFor(amount: 1)

        let data = try self.straw.read()

        try self.countLock.waitFor(amount: data.count - 1)

        self.window.increaseUpperBound(by: data.count)
        let result = SegmentData(data: data, window: window)

        self.functionLock.signal()

        return result
    }

    public func read(size: Int) throws -> SegmentData
    {
        self.functionLock.wait()

        try self.countLock.waitFor(amount: size)

        let data = try self.straw.read(size: size)
        self.window.increaseUpperBound(by: data.count)
        let result = SegmentData(data: data, window: window)

        self.functionLock.signal()

        return result
    }

    public func read(maxSize: Int) throws -> SegmentData
    {
        self.functionLock.wait()

        try self.countLock.waitFor(amount: 1)

        let data = try self.straw.read(maxSize: maxSize)

        try self.countLock.waitFor(amount: data.count - 1)

        self.window.increaseUpperBound(by: data.count)
        let result = SegmentData(data: data, window: window)

        self.functionLock.signal()

        return result
    }

    public func clear(tcp: InternetProtocols.TCP) throws
    {
        self.functionLock.wait()

        guard SequenceNumber(tcp.acknowledgementNumber) == self.window.lowerBound else
        {
            self.functionLock.signal()
            throw TCPUpstreamStrawError.segmentMismatch
        }

        self.window = SequenceNumberRange(lowerBound: tcp.window.upperBound, upperBound: self.window.upperBound)

        self.functionLock.signal()
    }
}
