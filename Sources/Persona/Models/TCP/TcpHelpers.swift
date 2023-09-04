//
//  TcpHelpers.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/5/23.
//

import Foundation

import InternetProtocols
import Net

let maximumSegmentLifetime = TimeInterval(integerLiteral: 2 * 60) // 2 minutes

public func sequenceLength(_ tcp: InternetProtocols.TCP) -> UInt32
{
    var length: UInt32 = 0
    
    if tcp.syn
    {
        length += 1
    }
    
    if tcp.fin
    {
        length += 1
    }
    
    if let payload = tcp.payload
    {
        length += UInt32(payload.count)
    }
    
    return length
}

// Initial sequence number generator - Section 3.3, page 27
/*
 To avoid confusion we must prevent segments from one incarnation of a
 connection from being used while the same sequence numbers may still
 be present in the network from an earlier incarnation.  We want to
 assure this, even if a TCP crashes and loses all knowledge of the
 sequence numbers it has been using.  When new connections are created,
 an initial sequence number (ISN) generator is employed which selects a
 new 32 bit ISN.  The generator is bound to a (possibly fictitious) 32
 bit clock whose low order bit is incremented roughly every 4
 microseconds.  Thus, the ISN cycles approximately every 4.55 hours.
 Since we assume that segments will stay in the network no more than
 the Maximum Segment Lifetime (MSL) and that the MSL is less than 4.55
 hours we can reasonably assume that ISN's will be unique.
 */
func isn() -> SequenceNumber
{
    let epochTimeIntervalInSeconds = Date().timeIntervalSince1970
    let microseconds = epochTimeIntervalInSeconds * 1000000
    let fourMicroseconds = microseconds / 4
    let wholeMicroseconds = fourMicroseconds.truncatingRemainder(dividingBy: Double(UInt32.max))
    let uint32 = UInt32(wholeMicroseconds)
    return SequenceNumber(uint32)
}

public func description(_ ipv4: IPv4, _ tcp: TCP) -> String
{
    return "\(ipv4.sourceAddress.ipv4AddressString ?? "?.?.?.?."):\(tcp.sourcePort) ~ \(ipv4.destinationAddress.ipv4AddressString ?? "?.?.?.?."):\(tcp.destinationPort) - \(describeFlags(tcp)), SEQ#:\(SequenceNumber(tcp.sequenceNumber)), ACK#:\(SequenceNumber(tcp.acknowledgementNumber)), windowSize:\(tcp.windowSize) - \(describePayload(tcp))"
}

func describeFlags(_ tcp: TCP) -> String
{
    var result: String = ""
    if tcp.syn
    {
        result = result + "S"
    }

    if tcp.ack
    {
        result = result + "A"
    }

    if tcp.fin
    {
        result = result + "F"
    }

    if tcp.rst
    {
        result = result + "R"
    }

    if result.isEmpty
    {
        result = "-"
    }

    return result
}

func describePayload(_ tcp: TCP) -> String
{
    if let payload = tcp.payload
    {
        return "\(payload.count) bytes"
    }
    else
    {
        return "no payload"
    }
}
