//
//  RetransmissionQueue.swift
//
//
//  Created by Dr. Brandon Wiley on 10/2/23.
//

import Foundation
import Logging

import InternetProtocols

public class RetransmissionQueue
{
    public let logger: Logger

    public var isEmpty: Bool
    {
        return self.queue.isEmpty
    }

    public var count: Int
    {
        return self.queue.count
    }

    public var bytes: Int
    {
        // Return the sum of the size of the data in each segment in the queue.
        return self.queue.map { $0.data.count }.reduce(0, +)
    }

    var queue: [Segment] = []

    public init(logger: Logger)
    {
        self.logger = logger
    }

    public func add(segment: Segment)
    {
        self.queue.append(segment)
    }

    // FIXME - handle rollover
    public func acknowledge(acknowledgementNumber: SequenceNumber)
    {
        self.queue = self.queue.filter
        {
            segment in

            // return true if we should keep this segment in the retransmission queue
            if acknowledgementNumber.uint32 < segment.window.lowerBound.uint32
            {
                self.logger.debug("🫐🫐 Received ack #: \(acknowledgementNumber). Our segment window lower bound is: \(segment.window.lowerBound.uint32), so we kept it for retransmission! 🫐🫐")
                return true
            }
            else
            {
                self.logger.debug("🍓🍓 Received ack #: \(acknowledgementNumber), Removed segment from the Retransmission Queue. Our segment window lower bound is: \(segment.window.lowerBound.uint32) 🍓🍓")
                return false
            }
        }
    }

    public func get(lowerBound: SequenceNumber) throws -> Segment
    {
        let result = self.queue.first { $0.window.lowerBound == lowerBound }

        guard let result else
        {
            throw RetransmissionQueueError.noCandidates
        }

        return result
    }
}

public enum RetransmissionQueueError: Error
{
    case queueIsEmpty
    case noCandidates
    case tooSoonToRetransmit
}
