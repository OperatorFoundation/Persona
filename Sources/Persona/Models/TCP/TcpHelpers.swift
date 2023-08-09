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

//func sendRst(sourceAddress: IPv4Address, sourcePort: UInt16, destinationAddress: IPv4Address, destinationPort: UInt16, _ tcp: InternetProtocols.TCP, _ state: States) async throws
//{
//    switch state
//    {
//        case .closed:
//            /*
//             If the state is CLOSED (i.e., TCB does not exist) then
//
//             all data in the incoming segment is discarded.  An incoming
//             segment containing a RST is discarded.  An incoming segment not
//             containing a RST causes a RST to be sent in response.  The
//             acknowledgment and sequence field values are selected to make the
//             reset sequence acceptable to the TCP that sent the offending
//             segment.
//
//             If the ACK bit is off, sequence number zero is used,
//
//             <SEQ=0><ACK=SEG.SEQ+SEG.LEN><CTL=RST,ACK>
//
//             If the ACK bit is on,
//
//             <SEQ=SEG.ACK><CTL=RST>
//
//             Return.
//             */
//
//        case .listen:
//            self.logger.debug("* TCP state is listen")
//            if tcp.ack
//            {
//                /*
//                 Any acknowledgment is bad if it arrives on a connection still in
//                 the LISTEN state.  An acceptable reset segment should be formed
//                 for any arriving ACK-bearing segment.  The RST should be
//                 formatted as follows:
//
//                 <SEQ=SEG.ACK><CTL=RST>
//                 */
//
//                self.logger.debug("* received tcp.ack, calling send packet with tcp.acknowledgementNumber, and ack: true")
//
//                self.tcpLogger.debug("(proxy)sendRst() called")
//                try await self.sendPacket(sourceAddress: sourceAddress, sourcePort: sourcePort, destinationAddress: destinationAddress, destinationPort: destinationPort, sequenceNumber: SequenceNumber(tcp.acknowledgementNumber), ack: true)
//            }
//            else
//            {
//                self.logger.debug("* no tcp.ack received, doing nothing")
//                return
//            }
//
//        default:
//            self.logger.debug("* TCP state is an unexpected value, doing nothing")
//            return
//    }
//}

//func sendPacket(sourceAddress: IPv4Address, sourcePort: UInt16, destinationAddress: IPv4Address, destinationPort: UInt16, sequenceNumber: SequenceNumber = SequenceNumber(0), acknowledgementNumber: SequenceNumber = SequenceNumber(0), ack: Bool = false) async throws
//{
//    guard let ipv4 = try? IPv4(sourceAddress: sourceAddress, destinationAddress: destinationAddress, sourcePort: sourcePort, destinationPort: destinationPort, sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, syn: false, ack: ack, fin: false, rst: true, windowSize: 0, payload: nil) else
//    {
//        self.logger.error("* sendPacket() failed to create an IPV4packet")
//        throw TcpProxyError.badIpv4Packet
//    }
//
//    try await self.client.writeWithLengthPrefix(ipv4.data, 32)
//}
