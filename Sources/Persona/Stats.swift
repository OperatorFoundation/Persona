//
//  Stats.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/15/23.
//

import Foundation

import Datable
import Gardener
import Puppy

public class Stats
{
    static public let writeInterval: Int = 1000 // packets

    public var messages: Int = 0
    public var nonIPv4: Int = 0
    public var nonTcpUdpIPv4: Int = 0
    public var ipv4: Int = 0
    public var tcp: Int = 0
    public var udp: Int = 0

    public var closed: Int = 0
    public var closeWait: Int = 0
    public var closing: Int = 0
    public var finWait1: Int = 0
    public var finWait2: Int = 0
    public var lastAck: Int = 0
    public var listen: Int = 0
    public var new: Int = 0
    public var synReceived: Int = 0
    public var synSent: Int = 0
    public var established: Int = 0
    public var syn: Int = 0
    public var fin: Int = 0
    public var rst: Int = 0
    public var ack: Int = 0
    public var noFlags: Int = 0
    public var payload: Int = 0
    public var noPayload: Int = 0
    public var inWindow: Int = 0
    public var outOfWindow: Int = 0

    public var sentipv4: Int = 0
    public var sentudp: Int = 0
    public var senttcp: Int = 0
    public var sentestablished: Int = 0
    public var sentsyn: Int = 0
    public var sentfin: Int = 0
    public var sentrst: Int = 0
    public var sentack: Int = 0
    public var sentpayload: Int = 0
    public var sentnopayload: Int = 0
    public var windowCorrection: Int = 0
    public var retransmission: Int = 0
    public var fresh: Int = 0

    var lastWrite: Date = Date() // now
    var lastSentPayload: Int = 0

    let logger: Puppy

    public init(logger: Puppy)
    {
        self.logger = logger
    }

    public func writeLog()
    {
        self.logger.info("--------------")
        self.logger.info(self.description)
        self.logger.info("--------------")

        self.lastWrite = Date() // now
        self.lastSentPayload = self.sentpayload
    }
}

extension Stats: CustomStringConvertible
{
    public var description: String
    {
        let ackRatio: Int
        if self.noPayload == 0
        {
            ackRatio = 0
        }
        else
        {
            ackRatio = Int(Double(self.noPayload) / (Double(self.sentpayload)) * 100)
        }

        let retransmissionRatio: Int
        if self.fresh == 0
        {
            retransmissionRatio = 0
        }
        else
        {
            retransmissionRatio = Int(Double(self.retransmission) / Double(self.fresh) * 100)
        }

        let now: Date = Date() // now
        let elapsed = Double(now.timeIntervalSince1970 - self.lastWrite.timeIntervalSince1970)

        let pps: Int
        if elapsed == 0
        {
            pps = 0
        }
        else
        {
            let accumulated = Double(self.sentpayload - self.lastSentPayload)
            pps = Int(accumulated / elapsed)
        }

        return """
        Received:
        non-IPv4         - \(self.nonIPv4)
        non-TCP/UDP IPv4 - \(self.nonTcpUdpIPv4)
        IPv4                      - \(self.ipv4)
        \tIPv4/UDP                - \(self.udp)
        \tIPv4/TCP                - \(self.tcp)
        \t\tCLOSED                - \(self.closed)
        \t\tCLOSE-WAIT            - \(self.closeWait)
        \t\tCLOSINGvvv            - \(self.closing)
        \t\tFIN-WAIT-1            - \(self.finWait1)
        \t\tFIN-WAIT-2            - \(self.finWait2)
        \t\tLAST-ACK              - \(self.lastAck)
        \t\tNEW                   - \(self.new)
        \t\tSYN-RECEIVED          - \(self.synReceived)
        \t\tSYN-SENT              - \(self.synSent)
        \t\tESTABLISHED           - \(self.established)
        \t\t\tno flags            - \(self.noFlags)
        \t\t\tSYN                 - \(self.syn)
        \t\t\tFIN                 - \(self.fin)
        \t\t\tRST                 - \(self.rst)
        \t\t\tACK                 - \(self.ack)
        \t\t\t\tin window         - \(self.inWindow)
        \t\t\t\tout of window     - \(self.outOfWindow)
        \t\t\t\tpayload           - \(self.payload)
        \t\t\t\tno payload        - \(self.noPayload)

        Sent:
        IPv4                      - \(self.sentipv4)
        \tIPv4/UDP                - \(self.sentudp)
        \tIPv4/TCP                - \(self.senttcp)
        \t\tESTABLISHED           - \(self.sentestablished)
        \t\t\tSYN                 - \(self.sentsyn)
        \t\t\tFIN                 - \(self.sentfin)
        \t\t\tRST                 - \(self.sentrst)
        \t\t\tACK                 - \(self.sentack)
        \t\t\t\tpayload           - \(self.sentpayload)
        \t\t\t\tno payload        - \(self.sentnopayload)
        \t\t\t\twindow correction - \(self.windowCorrection)
        \t\t\t\tretransmission\t- \(self.retransmission)
        \t\t\t\tfresh\t- \(self.fresh)

        Metrics:
        \toptimism                - \(TcpProxy.optimism)
        \tack ratio               - \(ackRatio)%
        \tretransmisison ratio\t- \(retransmissionRatio)%
        \tpackets per second\t-(pps) pps
        """
    }
}
