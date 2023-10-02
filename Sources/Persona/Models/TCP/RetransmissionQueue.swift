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

            return !segment.window.contains(sequenceNumber: acknowledgementNumber)
        }
    }

    public func next() throws -> Segment
    {
        guard self.queue.count > 0 else
        {
            throw RetransmissionQueueError.queueIsEmpty
        }

        let now = Date() // now

        let candidates = self.queue.filter
        {
            segment in

            let elapsed = now.timeIntervalSince1970 - segment.timestamp.timeIntervalSince1970

            return elapsed >= Self.retransmitTime
        }

        guard self.queue.count > 0 else
        {
            throw RetransmissionQueueError.noCandidates
        }

        let sorted = candidates.sorted
        {
            lhs, rhs in

            return lhs.timestamp > rhs.timestamp
        }

        guard let result = sorted.first else
        {
            throw RetransmissionQueueError.noCandidates
        }

        result.timestamp = now

        return result
    }
}

public enum RetransmissionQueueError: Error
{
    case queueIsEmpty
    case noCandidates
}
