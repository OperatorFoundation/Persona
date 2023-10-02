//
//  Segment.swift
//
//
//  Created by Dr. Brandon Wiley on 10/2/23.
//

import Foundation

import InternetProtocols

public class Segment
{
    let data: Data
    let window: SequenceNumberRange
    var timestamp: Date

    public convenience init(data: Data, sequenceNumber: SequenceNumber)
    {
        let window = SequenceNumberRange(lowerBound: sequenceNumber, size: UInt32(data.count))
        let timestamp = Date() // now

        self.init(data: data, window: window, timestamp: timestamp)
    }

    public init(data: Data, window: SequenceNumberRange, timestamp: Date)
    {
        self.data = data
        self.window = window
        self.timestamp = timestamp
    }
}
