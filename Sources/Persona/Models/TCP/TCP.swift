//
//  TCP.swift
//  
//
//  Created by Dr. Brandon Wiley on 3/1/22.
//

import Foundation
import InternetProtocols
import SwiftQueue

// https://datatracker.ietf.org/doc/html/rfc793

public class TCP
{
    static let maximumSegmentLifetime = TimeInterval(integerLiteral: 2 * 60) // 2 minutes
    static var quietTimeLock: DispatchSemaphore = DispatchSemaphore(value: 0)
    static var quietTime: Timer? = Timer(timeInterval: TCP.maximumSegmentLifetime, repeats: false)
    {
        timer in

        TCP.quietTime = nil
        TCP.quietTimeLock.signal()
    }

    public enum States
    {
        case listen
        case synSent
        case synReceived
        case established
        case finWait1
        case finWait2
        case closeWait
        case closing
        case lastAck
        case timeWait
        case closed
    }

    public enum Events: Equatable
    {
        case passiveOpen
        case activeOpen
        case send(Data, Bool) // Push
        case receive
        case close
        case timeout
        case status

        static public func ==(_ x: Events, y: Events) -> Bool
        {
            switch x
            {
                case .passiveOpen:
                    switch y
                    {
                        case .passiveOpen:
                            return true
                        default:
                            return false
                    }
                case .activeOpen:
                    switch y
                    {
                        case .activeOpen:
                            return true
                        default:
                            return false
                    }
                case .send(_, _):
                    switch y
                    {
                        case .send(_, _):
                            return true
                        default:
                            return false
                    }
                case .receive:
                    switch y
                    {
                        case .receive:
                            return true
                        default:
                            return false
                    }
                case .close:
                    switch y
                    {
                        case .close:
                            return true
                        default:
                            return false
                    }
                case .timeout:
                    switch y
                    {
                        case .timeout:
                            return true
                        default:
                            return false
                    }
                case .status:
                    switch y
                    {
                        case .status:
                            return true
                        default:
                            return false
                    }
            }
        }
    }

    public enum UserAlerts
    {
        case networkClosing
        case dataReceived
    }

    var state: States
    var sendSequenceNumber: SequenceNumber = SequenceNumber(0)
    var receiveSequenceNumber: SequenceNumber = SequenceNumber(0)
    var closeTimer: Timer?
    var didListen: Bool = false
    var sendQueue: Queue<InternetProtocols.TCP> = Queue<InternetProtocols.TCP>()
    var receiveQueue: Queue<InternetProtocols.TCP> = Queue<InternetProtocols.TCP>()
    var maximumSegmentSize: UInt16? = nil

    public init()
    {
        state = .closed
    }

    public enum Options: UInt8
    {
        case endOfOptionList = 0
        case noOperation = 1
        case maximumSegmentSize = 2
    }

    public func segmentLength(_ tcp: InternetProtocols.TCP) -> Int
    {
        if let payload = tcp.payload
        {
            return payload.count
        }
        else
        {
            return 0
        }
    }

    public func handleOptions(_ data: Data)
    {
        guard data.count >= 1 else
        {
            return
        }

        if data.count == 1
        {
            return
        }
        else
        {
            guard let optionKind = Options(rawValue: data[0]) else
            {
                return
            }

            let optionLength = Int(data[1])

            guard data.count >= optionLength else
            {
                return
            }

            let options = data[2..<optionLength]

            switch optionKind
            {
                case .maximumSegmentSize:
                    guard let mss = options.maybeNetworkUint16 else
                    {
                        return
                    }

                    self.maximumSegmentSize = mss

                default:
                    return
            }
        }
    }
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
func isn() throws -> SequenceNumber
{
    guard TCP.quietTime == nil else
    {
        throw TcpError.quietTime
    }

    let epochTimeIntervalInSeconds = Date().timeIntervalSince1970
    let microseconds = epochTimeIntervalInSeconds * 1000000
    let fourMicroseconds = microseconds / 4
    let uint32 = UInt32(fourMicroseconds)
    return SequenceNumber(uint32)
}

public enum TcpError: Error
{
    case quietTime
    case connectionClosed
}
