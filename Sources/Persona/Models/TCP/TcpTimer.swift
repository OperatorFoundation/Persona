//
//  TcpTimer.swift
//  
//
//  Created by Dr. Brandon Wiley on 6/28/24.
//

import Logging
import Foundation

import Chord
import Datable
import InternetProtocols
import Net
import Puppy
import TransmissionAsync

public struct TcpProxyTimerRequest: CustomStringConvertible
{
    public var description: String
    {
        return "[TCP Timer Request \(self.identity):\(self.sequenceNumber)]"
    }

    public var data: Data
    {
        let typeBytes = Data(array: [Subsystem.Timer.rawValue])
        let identityBytes = self.identity.data
        let lowerBoundBytes: Data
        if let sequenceNumberBytes = self.sequenceNumber.uint32.maybeNetworkData
        {
            lowerBoundBytes = sequenceNumberBytes
        }
        else
        {
            // This should never happen.
            // It's a hack to avoid force-unwrapping because this data property is non-optional,
            // but self.sequenceNumber.uint32.maybeNetworkData is optional due to protocol
            // comformance to MaybeNetworkDatable, but not actually optional in its implementation.
            lowerBoundBytes = Data(repeating: 0, count: 4)
        }

        return typeBytes + identityBytes + lowerBoundBytes
    }

    let identity: Identity
    let sequenceNumber: SequenceNumber

    public init(identity: Identity, sequenceNumber: SequenceNumber)
    {
        self.identity = identity
        self.sequenceNumber = sequenceNumber
    }
}

public struct TcpProxyTimerResponse: CustomStringConvertible
{
    public var description: String
    {
        return "[TCP Timer Response \(self.identity):\(self.sequenceNumber)]"
    }

    let identity: Identity
    let sequenceNumber: SequenceNumber

    public init(identity: Identity, sequenceNumber: SequenceNumber)
    {
        self.identity = identity
        self.sequenceNumber = sequenceNumber
    }

    public init(data: Data) throws
    {
        guard data.count >= 16 else
        {
            throw TcpProxyError.shortMessage
        }

        let identityBytes = Data(data[0..<12])
        let rest = Data(data[12...])

        let identity = try Identity(data: identityBytes)
        let sequenceNumber = SequenceNumber(data: rest)

        self.init(identity: identity, sequenceNumber: sequenceNumber)
    }
}
