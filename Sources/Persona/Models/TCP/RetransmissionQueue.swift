//
//  RetransmissionQueue.swift
//
//
//  Created by Dr. Brandon Wiley on 10/2/23.
//

import Foundation

import InternetProtocols

public class RetransmissionQueue
{
    static public let retransmitTime: Double = 0.1 // 100 ms in seconds

    public var isEmpty: Bool
    {
        return self.queue.isEmpty
    }

    var queue: [Segment] = []

    public init()
    {
    }

    public func add(segment: Segment)
    {
        self.queue.append(segment)
    }

    public func remove(sequenceNumber: SequenceNumber)
    {
        self.queue = self.queue.filter
        {
            segment in

            segment.window.lowerBound != sequenceNumber
        }
    }

    public func acknowledge(acknowledgementNumber: SequenceNumber)
    {
        self.queue = self.queue.filter
        {
            segment in

            // return true if we should keep this segment in the retransmission queue
            return acknowledgementNumber.uint32 < segment.window.lowerBound.uint32 // FIXME - handle rollover
        }
    }

    public func next() throws -> Segment
    {
        guard let segment = self.queue.first else
        {
            throw RetransmissionQueueError.queueIsEmpty
        }

        let now = Date().timeIntervalSince1970 // now
        let then = segment.timestamp.timeIntervalSince1970
        let elapsed = now - then

        if elapsed >= Self.retransmitTime
        {
            return segment
        }
        else
        {
            throw RetransmissionQueueError.tooSoonToRetransmit
        }
    }
}

public enum RetransmissionQueueError: Error
{
    case queueIsEmpty
    case noCandidates
    case tooSoonToRetransmit
}
