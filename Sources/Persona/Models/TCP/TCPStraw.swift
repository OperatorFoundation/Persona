//
//  TCPSendStrawActor.swift
//
//
//  Created by Dr. Brandon Wiley on 9/27/22.
//

import Foundation
import Logging

import InternetProtocols
import Straw

// Data traveling from server to client needs to be buffered until it is ACKed by the client.
// We track the sequence numbers on the buffered data.
//
// Data traveling from client to server is not buffered, but we track the acknowledgement number so that we can send ACKs.
public class TCPStraw
{
    static let serverWindowSize: UInt16 = 65535

    public var isEmpty: Bool
    {
        return self.straw.isEmpty
    }

    public var count: Int
    {
        return self.straw.count
    }

    // Private let properties
    let straw = UnsafeStraw() // No need for thread safety in this implementation as only one thread accesses the Straw.

    let logger: Logger

    // Private var properties

    // The starting sequence number of the buffered data moving from server to client.
    var sequenceNumber: SequenceNumber

    // The tracked acknowledgement number of the data that has been moved from client to server.
    var acknowledgementNumber: SequenceNumber
    var open = true

    // Public constructors
    public init(logger: Logger, sequenceNumber: SequenceNumber, acknowledgementNumber: SequenceNumber)
    {
        self.logger = logger
        self.sequenceNumber = sequenceNumber
        self.acknowledgementNumber = acknowledgementNumber
    }

    public func getState() -> (SequenceNumber, SequenceNumber, UInt16)
    {
        return (self.sequenceNumber, self.acknowledgementNumber, Self.serverWindowSize)
    }

    // Check if a packet from the client is within the receive window.
    func inWindow(_ tcp: InternetProtocols.TCP) -> Bool
    {
        let sequenceNumberData = tcp.sequenceNumber
        let tcpSequenceNumber = SequenceNumber(sequenceNumberData)

        let window = SequenceNumberRange(lowerBound: self.acknowledgementNumber, size: UInt32(Self.serverWindowSize))
        guard window.contains(sequenceNumber: tcpSequenceNumber) else
        {
            return false
        }

        if let payload = tcp.payload
        {
            let tcpUpperBound = tcpSequenceNumber.add(payload.count)

            guard window.contains(sequenceNumber: tcpUpperBound) else
            {
                return false
            }
        }

        return true
    }

    // This is the client window
    public func clientWindow(size: UInt16) -> SequenceNumberRange
    {
        return SequenceNumberRange(lowerBound: self.acknowledgementNumber, size: UInt32(size))
    }

    public func serverWindow() -> SequenceNumberRange
    {
        return SequenceNumberRange(lowerBound: self.acknowledgementNumber, size: UInt32(Self.serverWindowSize))
    }

    // Public functions

    // Buffer data from the server until it is ACKed by the client.
    public func write(_ data: Data) throws
    {
        guard self.open else
        {
            throw TCPDownstreamStrawError.strawClosed
        }

        self.straw.write(data)
    }

    public func read() throws -> SegmentData
    {
        let data = try self.straw.read()
        let window = SequenceNumberRange(lowerBound: self.sequenceNumber, size: UInt32(data.count))
        let result = SegmentData(data: data, window: window)
        self.sequenceNumber = self.sequenceNumber.add(data.count)

        return result
    }

    public func read(size: Int) throws -> SegmentData
    {
        let data = try self.straw.read(size: size)
        let window = SequenceNumberRange(lowerBound: self.sequenceNumber, size: UInt32(data.count))
        let result = SegmentData(data: data, window: window)
        self.sequenceNumber = self.sequenceNumber.add(data.count)
        
        return result
    }

    public func read(maxSize: Int) throws -> SegmentData
    {
        let data = try self.straw.read(maxSize: maxSize)
        let window = SequenceNumberRange(lowerBound: self.sequenceNumber, size: UInt32(data.count))
        let result = SegmentData(data: data, window: window)
        self.sequenceNumber = self.sequenceNumber.add(data.count)

        return result
    }

    public func incrementSequenceNumber()
    {
        self.sequenceNumber = self.sequenceNumber.increment()
    }

    public func increaseAcknowledgementNumber(_ x: Int)
    {
        self.acknowledgementNumber = self.acknowledgementNumber.add(x)
    }

    public func decrementAcknowledgementNumber()
    {
        self.acknowledgementNumber = self.acknowledgementNumber.decrement()
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

public enum TCPDownstreamStrawError: Error
{
    case misorderedSegment(expected: SequenceNumber, actual: SequenceNumber)
    case strawClosed
}
