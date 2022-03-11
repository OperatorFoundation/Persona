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

    public func processPacket(_ tcp: InternetProtocols.TCP) throws -> UserAlerts?
    {
        switch self.state
        {
            case .listen:
                if tcp.syn
                {
                    self.receiveSequenceNumber = SequenceNumber(tcp.sequenceNumber).increment()
                    self.sendSequenceNumber = try isn()
                    self.sndSynAck(tcp)
                    self.didListen = true
                    self.state = .synReceived

                    if let options = tcp.options
                    {
                        self.handleOptions(options)
                    }
                }
                else if tcp.ack
                {
                    let sequenceNumber = SequenceNumber(tcp.acknowledgementNumber)
                    let acknowledgementNumber = sequenceNumber.add(self.segmentLength(tcp))
                    self.sndRst(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber)
                }
                else if tcp.rst
                {
                    return nil
                }
                else if tcp.fin
                {
                    self.receiveSequenceNumber = SequenceNumber(tcp.sequenceNumber).increment()
                    self.sndAck(tcp)
                }
                else
                {
                    let sequenceNumber = SequenceNumber(0)
                    let acknowledgementNumber = SequenceNumber(0)
                    self.sndRst(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber)
                }

                return nil

            case .synSent:
                if tcp.syn && tcp.ack
                {
                    self.receiveSequenceNumber = SequenceNumber(tcp.sequenceNumber).increment()
                    self.sndAck(tcp)

                    if SequenceNumber(tcp.acknowledgementNumber) == self.sendSequenceNumber
                    {
                        self.state = .established
                    }
                    else
                    {
                        let sequenceNumber = SequenceNumber(tcp.acknowledgementNumber)
                        let acknowledgementNumber = sequenceNumber.add(self.segmentLength(tcp))
                        self.sndRst(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber)
                    }

                    if let options = tcp.options
                    {
                        self.handleOptions(options)
                    }
                }
                else if tcp.syn
                {
                    self.receiveSequenceNumber = SequenceNumber(tcp.sequenceNumber).increment()
                    self.sndAck(tcp)
                    self.state = .synReceived

                    if let options = tcp.options
                    {
                        self.handleOptions(options)
                    }
                }
                else if tcp.ack
                {
                    if SequenceNumber(tcp.acknowledgementNumber) != self.sendSequenceNumber
                    {
                        let sequenceNumber = SequenceNumber(tcp.acknowledgementNumber)
                        let acknowledgementNumber = sequenceNumber.add(self.segmentLength(tcp))
                        self.sndRst(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber)
                    }
                    // FIXME - what about if the ack matches?
                }
                else if tcp.fin
                {
                    self.receiveSequenceNumber = SequenceNumber(tcp.sequenceNumber).increment()
                    self.sndAck(tcp)
                }
                else if tcp.rst
                {
                    if SequenceNumber(tcp.acknowledgementNumber) == self.sendSequenceNumber
                    {
                        self.state = .listen
                    }
                }
                else
                {
                    let sequenceNumber = SequenceNumber(0)
                    let acknowledgementNumber = SequenceNumber(0)
                    self.sndRst(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber)
                }

                return nil

            case .synReceived:
                if tcp.ack
                {
                    if SequenceNumber(tcp.acknowledgementNumber) == self.sendSequenceNumber
                    {
                        self.didListen = false
                        self.state = .established
                    }
                    else
                    {
                        let sequenceNumber = SequenceNumber(tcp.acknowledgementNumber)
                        let acknowledgementNumber = sequenceNumber.add(self.segmentLength(tcp))
                        self.sndRst(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber)
                    }
                }
                else if tcp.rst
                {
                    if self.inWindow(tcp)
                    {
                        if self.didListen
                        {
                            self.state = .listen
                        }
                        else
                        {
                            self.didListen = false
                            self.state = .closed
                        }
                    }
                }
                else if tcp.fin
                {
                    self.receiveSequenceNumber = SequenceNumber(tcp.sequenceNumber).increment()
                    self.sndAck(tcp)
                }
                else
                {
                    let sequenceNumber = SequenceNumber(0)
                    let acknowledgementNumber = SequenceNumber(0)
                    self.sndRst(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber)
                }

                return nil

            case .established:
                if tcp.fin
                {
                    self.receiveSequenceNumber = self.receiveSequenceNumber.increment()
                    self.sndAck(tcp)
                    self.state = .closeWait
                }
                else if tcp.rst
                {
                    if self.inWindow(tcp)
                    {
                        self.state = .listen
                    }
                }
                else
                {
                    // FIXME - handle data, good acks, bad acks, and out of window sequence numbers
                    self.receiveQueue.enqueue(tcp)
                }

                return nil

            case .finWait1:
                if tcp.fin
                {
                    self.receiveSequenceNumber = self.receiveSequenceNumber.increment()
                    self.sndAck(tcp)
                    self.state = .closing
                }
                else if tcp.ack
                {
                    if SequenceNumber(tcp.acknowledgementNumber) == self.sendSequenceNumber
                    {
                        self.state = .established
                    }
                }
                else if tcp.rst
                {
                    if self.inWindow(tcp)
                    {
                        self.state = .listen
                    }
                }
                else
                {
                    self.sndAck(tcp)
                }

                return nil

            case .finWait2:
                if tcp.fin
                {
                    self.receiveSequenceNumber = self.receiveSequenceNumber.increment()
                    self.sndAck(tcp)
                    self.state = .timeWait
                }
                else if tcp.rst
                {
                    if self.inWindow(tcp)
                    {
                        self.state = .listen
                    }
                }
                else
                {
                    self.sndAck(tcp)
                }

                return nil

            case .closing:
                if tcp.ack
                {
                    if SequenceNumber(tcp.acknowledgementNumber) == self.sendSequenceNumber
                    {
                        self.closeTimer = Timer(timeInterval: TCP.maximumSegmentLifetime * 2, repeats: false)
                        {
                            timer in

                            self.state = .closed
                        }

                        self.state = .timeWait
                    }
                }
                else if tcp.rst
                {
                    if self.inWindow(tcp)
                    {
                        self.state = .listen
                    }
                }
                else if tcp.fin
                {
                    self.receiveSequenceNumber = SequenceNumber(tcp.sequenceNumber).increment()
                    self.sndAck(tcp)
                }
                else
                {
                    self.sndAck(tcp)
                }

                return nil

            case .lastAck:
                if tcp.ack
                {
                    if SequenceNumber(tcp.acknowledgementNumber) == self.sendSequenceNumber
                    {
                        self.state = .closed
                    }
                }
                else if tcp.rst
                {
                    if self.inWindow(tcp)
                    {
                        self.state = .listen
                    }
                }
                else if tcp.fin
                {
                    self.receiveSequenceNumber = SequenceNumber(tcp.sequenceNumber).increment()
                    self.sndAck(tcp)
                }
                else
                {
                    self.sndAck(tcp)
                }

                return nil

            case .closeWait:
                if tcp.fin
                {
                    self.receiveSequenceNumber = SequenceNumber(tcp.sequenceNumber).increment()
                    self.sndAck(tcp)
                }
                else
                {
                    self.sndAck(tcp)
                }

                return nil

            case .timeWait:
                if tcp.fin
                {
                    self.receiveSequenceNumber = SequenceNumber(tcp.sequenceNumber).increment()
                    self.sndAck(tcp)
                }
                else
                {
                    self.sndAck(tcp)
                }

                return nil

            /*
             1.  If the connection does not exist (CLOSED) then a reset is sent
             in response to any incoming segment except another reset.  In
             particular, SYNs addressed to a non-existent connection are rejected
             by this means.

             If the incoming segment has an ACK field, the reset takes its
             sequence number from the ACK field of the segment, otherwise the
             reset has sequence number zero and the ACK field is set to the sum
             of the sequence number and segment length of the incoming segment.
             The connection remains in the CLOSED state.
             */
            case .closed:
                if tcp.rst
                {
                    self.state = .listen
                }
                else if tcp.ack
                {
                    let sequenceNumber = SequenceNumber(tcp.acknowledgementNumber)
                    let acknowledgementNumber = sequenceNumber.add(self.segmentLength(tcp))
                    self.sndRst(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber)
                }
                else
                {
                    let sequenceNumber = SequenceNumber(0)
                    let acknowledgementNumber = SequenceNumber(0)
                    self.sndRst(sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber)
                }

                return nil
        }
    }

    public enum Options: UInt8
    {
        case endOfOptionList = 0
        case noOperation = 1
        case maximumSegmentSize = 2
    }

    public func processEvent(_ event: Events) throws -> UserAlerts?
    {
        switch self.state
        {
            case .closed:
                switch event
                {
                    case .passiveOpen:
                        self.createTCB()
                        self.state = .listen

                    case .activeOpen:
                        self.createTCB()

                        self.sendSequenceNumber = try isn()

                        self.sndSyn()
                        self.state = .synSent

                    default:
                        return nil
                }

                return nil

            case .listen:
                switch event
                {
                    case .send(_, _):
                        self.sendSequenceNumber = try isn()

                        self.sndSyn()
                        self.state = .synSent

                        return nil

                    default:
                        return nil
                }

            case .synReceived:
                if event == .close
                {
                    self.sndFin()
                    self.state = .finWait1
                }

                return nil

            case .established:
                switch event
                {
                    case .close:
                        self.sndFin()
                        self.state = .finWait1

                        return nil

                    case .send(let data, let push):
                        self.sndData(data: data)

                        if push
                        {
                            self.flushSendQueue()
                        }

                        return nil

                    default:
                        return nil
                }

            case .closeWait:
                if event == .close
                {
                    self.sndFin()
                    self.state = .lastAck
                }

                return nil

            case .timeWait:
                if event == .timeout
                {
                    self.deleteTCB()
                    self.state = .closed
                }

                return nil

            case .finWait1:
                switch event
                {
                    case .send(_, _):
                        throw TcpError.connectionClosed

                    default:
                        return nil
                }

            default:
                return nil
        }
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

    public func inWindow(_ tcp: InternetProtocols.TCP) -> Bool
    {
        // FIXME
        return true
    }

    public func createTCB()
    {
        // FIXME - implement
    }

    public func deleteTCB()
    {
        // FIXME - implement
    }

    public func sndSyn()
    {
        // FIXME - implement
        self.sendSequenceNumber = self.sendSequenceNumber.increment()
    }

    public func sndSynAck(_ tcp: InternetProtocols.TCP)
    {
        // FIXME - implement
    }

    public func sndAck(_ tcp: InternetProtocols.TCP)
    {
        // FIXME - implement
    }

    public func sndFin()
    {
        // FIXME - implement
    }

    public func sndRst(sequenceNumber: SequenceNumber, acknowledgementNumber: SequenceNumber)
    {
        // FIXME - implement
    }

    public func sndData(data: Data)
    {
        // FIXME - implement
    }

    public func flushSendQueue()
    {
        // FIXME - implement
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
