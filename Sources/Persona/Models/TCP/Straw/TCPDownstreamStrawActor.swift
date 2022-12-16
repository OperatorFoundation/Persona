//
//  TCPSendStrawActor.swift
//
//
//  Created by Dr. Brandon Wiley on 9/27/22.
//

import Foundation

import InternetProtocols
import Straw

public actor TCPDownstreamStrawActor
{
    let straw = SynchronizedStraw()
    var window: SequenceNumberRange
    let ackLock: LatchingLock = LatchingLock()
    var windowSize: UInt16

    public init(segmentStart: SequenceNumber, windowSize: UInt16)
    {
        self.window = SequenceNumberRange(lowerBound: segmentStart, size: windowSize)
        self.windowSize = windowSize
    }

    public func write(_ data: Data) throws
    {
        self.straw.write(data)
        self.window.increaseUpperBound(by: data.count)
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

    public func clear(tcp: InternetProtocols.TCP) throws
    {
        guard SequenceNumber(tcp.acknowledgementNumber) == self.window.lowerBound else
        {
            throw TCPUpstreamStrawError.segmentMismatch
        }

        self.window = SequenceNumberRange(lowerBound: tcp.window.upperBound, upperBound: self.window.upperBound)

        self.ackLock.latch()
    }

    public func getSequenceNumber() -> SequenceNumber
    {
        //self.ackLock.wait()

        return self.window.lowerBound
    }

    public func getWindowSize() -> UInt16
    {
        return self.windowSize
    }

    public func updateWindowSize(_ windowSize: UInt16)
    {
        self.windowSize = windowSize
    }
}
