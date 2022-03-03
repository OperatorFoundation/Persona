//
//  File.swift
//  
//
//  Created by Dr. Brandon Wiley on 3/2/22.
//

import Foundation
import Net
import SwiftQueue

public class TransmissionControlBlock
{
    static public var connections: [ConnectionName: TransmissionControlBlock] = [:]

    let name: ConnectionName
    let style: OpenStyle
    let unspecifiedRemoteAddress: Bool
    var sendBuffer: Data = Data()
    var receiveBuffer: Data = Data()
    var retransmitQueue = Queue<TCP>()

    let sndUna: SequenceNumber = SequenceNumber(0)
    let sndNxt: SequenceNumber = SequenceNumber(0)
    let sndWnd: UInt32 = 0
    let sndUp: UInt16 = 0
    let sndWl1: SequenceNumber = SequenceNumber(0)
    let sndWl2: SequenceNumber = SequenceNumber(0)
    let iss: SequenceNumber = SequenceNumber(0)

    let rcvNext: SequenceNumber = SequenceNumber(0)
    let rcvWnd: UInt32 = 0
    let rcvUp: UInt16 = 0
    let irs: SequenceNumber = SequenceNumber(0)

    let segSeq: SequenceNumber = SequenceNumber(0)
    let segAck: SequenceNumber = SequenceNumber(0)
    let segLen: UInt32 = 0
    let segWnd: UInt32 = 0
    let segUp: UInt16 = 0
    let segPrc: UInt16 = 0

    static public func open(local: NWEndpoint, remote: NWEndpoint, style: OpenStyle) throws -> ConnectionName
    {
        let tcb = try TransmissionControlBlock(local: local, remote: remote, style: style)
        TransmissionControlBlock.connections[tcb.name] = tcb

        return tcb.name
    }

    static public func isAllZeros(host: NWEndpoint.Host) throws -> Bool
    {
        switch host
        {
            case .ipv4(let ipv4):
                let data = ipv4.data
                return data.allSatisfy
                {
                    uint8 in

                    uint8 == 0
                }

            case .ipv6(let ipv6):
                let data = ipv6.data
                return data.allSatisfy
                {
                    uint8 in

                    uint8 == 0
                }

            default:
                throw TcbError.hostMustByIPAddress
        }
    }

    public init(local: NWEndpoint, remote: NWEndpoint, style: OpenStyle) throws
    {
        self.style = style

        let name = ConnectionName(local: local, remote: remote)
        self.name = name

        switch local
        {
            case .hostPort(host: let host, _):
                if try TransmissionControlBlock.isAllZeros(host: host)
                {
                    guard style == .passive else
                    {
                        throw TcbError.unspecifiedRemoteAddressRequiresPassiveOpen
                    }

                    self.unspecifiedRemoteAddress = true
                }
                else
                {
                    self.unspecifiedRemoteAddress = false
                }
            default:
                throw TcbError.hostMustByIPAddress
        }
    }

    public func acceptableAck(_ ack: SequenceNumber) -> Bool
    {
        return (self.sndUna < ack) && (ack <= self.sndNxt)
    }
}

public struct ConnectionName: Equatable, Hashable
{
    static public func ==(_ x: ConnectionName, _ y: ConnectionName) -> Bool
    {
        return x.local == y.local && x.remote == y.remote
    }

    let local: NWEndpoint
    let remote: NWEndpoint

    public init(local: NWEndpoint, remote: NWEndpoint)
    {
        self.local = local
        self.remote = remote
    }

    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(self.local)
        hasher.combine(self.remote)
    }
}

public enum OpenStyle
{
    case active
    case passive
}

public enum TcbError: Error
{
    case notAvailable
    case unspecifiedRemoteAddressRequiresPassiveOpen
    case hostMustByIPAddress
}
