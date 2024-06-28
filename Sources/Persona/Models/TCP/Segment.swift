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

    public convenience init(data: Data, sequenceNumber: SequenceNumber)
    {
        let window = SequenceNumberRange(lowerBound: sequenceNumber, size: UInt32(data.count))

        self.init(data: data, window: window)
    }

    public init(data: Data, window: SequenceNumberRange)
    {
        self.data = data
        self.window = window
    }
}
