//
//  TcpProxy.swift
//
//
//  Created by Dr. Brandon Wiley on 3/7/22.
//

import Logging
import Foundation

import Chord
import InternetProtocols
import Net
import Puppy
import TransmissionAsync

public actor TcpProxy
{
    static let maximumSegmentLifetime = TimeInterval(integerLiteral: 2 * 60) // 2 minutes
    static var quietTimeLock: DispatchSemaphore = DispatchSemaphore(value: 0)
    static var quietTime: Timer? = Timer(timeInterval: TcpProxy.maximumSegmentLifetime, repeats: false)
    {
        timer in

        TcpProxy.quietTime = nil
        TcpProxy.quietTimeLock.signal()
    }

    static public func sequenceLength(_ tcp: InternetProtocols.TCP) -> UInt32
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

    let logger: Logger
    let tcpLogger: Puppy?

    let client: AsyncConnection

    var connections: [TcpProxyConnection] = []

    public init(client: AsyncConnection, quietTime: Bool = true, logger: Logger, tcpLogger: Puppy?)
    {
        self.client = client
        self.logger = logger
        self.tcpLogger = tcpLogger

        if quietTime
        {
            TcpProxy.quietTimeLock.wait()
        }
    }

    public func processUpstreamPacket(_ packet: Packet) async throws
    {
        self.logger.debug("\n* Persona.TcpProxy: Attempting to process a TCP packet.")

        guard let ipv4Packet = packet.ipv4 else
        {
            throw TcpProxyError.notIPv4Packet(packet)
        }

        guard let sourceAddress = IPv4Address(ipv4Packet.sourceAddress) else
        {
            throw TcpProxyError.invalidAddress(ipv4Packet.sourceAddress)
        }
        self.logger.debug("* Source Address: \(sourceAddress.string)")

        guard let destinationAddress = IPv4Address(ipv4Packet.destinationAddress) else
        {
            throw TcpProxyError.invalidAddress(ipv4Packet.destinationAddress)
        }
        self.logger.debug("* Destination Address: \(destinationAddress)")

        guard let tcp = packet.tcp else
        {
            throw TcpProxyError.notTcpPacket(packet)
        }

        let sourcePort = tcp.sourcePort
        self.logger.debug("* Source Port: \(sourcePort)")

        let destinationPort = tcp.destinationPort
        self.logger.debug("* Destination Port: \(destinationPort)")

        if let proxyConnection = self.findConnection(localAddress: sourceAddress, localPort: sourcePort, remoteAddress: destinationAddress, remotePort: destinationPort, tcp: tcp)
        {
            try await proxyConnection.processUpstreamPacket(tcp)
        }
        else
        {
            try await self.handleNewConnection(tcp: tcp, sourceAddress: sourceAddress, sourcePort: sourcePort, destinationAddress: destinationAddress, destinationPort: destinationPort)
        }
    }

    func handleNewConnection(tcp: InternetProtocols.TCP, sourceAddress: IPv4Address, sourcePort: UInt16, destinationAddress: IPv4Address, destinationPort: UInt16) async throws
    {
        // When we receive a packet bound for a new destination,
        // if we can connect to that destination,
        //      we respond as if we are in the LISTEN state
        // otherwise,
        //      we respond as if we are in the CLOSED state

        if tcp.rst
        {
            /*
             If the state is LISTEN then

             first check for an RST

             An incoming RST should be ignored.  Return.
             */

            return
        }
        else if tcp.ack
        {
            /*
             second check for an ACK

             Any acknowledgment is bad if it arrives on a connection still in
             the LISTEN state.  An acceptable reset segment should be formed
             for any arriving ACK-bearing segment.  The RST should be
             formatted as follows:

             <SEQ=SEG.ACK><CTL=RST>

             Return.
             */

            try await self.sendRst(sourceAddress: sourceAddress, sourcePort: sourcePort, destinationAddress: destinationAddress, destinationPort: destinationPort, tcp, .listen)
            return
        }
        else if tcp.syn // A new connection requires a SYN packet
        {
            if tcp.destinationPort == 2234
            {
                tcpLogger?.debug("\n************************************************************")
                tcpLogger?.debug("* ⮕ SYN SEQ:\(SequenceNumber(tcp.sequenceNumber)) ❣️")
                tcpLogger?.debug("\n************************************************************")
            }

            // connect() automatically send a syn-ack back for the syn internally
            do
            {
                let networkConnection = try await AsyncTcpSocketConnection("127.0.0.1", 1232, self.logger)
                try await networkConnection.write(destinationAddress.data + destinationPort.maybeNetworkData!)
                try await self.addConnection(proxy: self, localAddress: sourceAddress, localPort: sourcePort, remoteAddress: destinationAddress, remotePort: destinationPort, connection: networkConnection, irs: SequenceNumber(tcp.sequenceNumber), rcvWnd: tcp.windowSize)
            }
            catch
            {
                // Connection failed.
                self.logger.error("* Persona failed to connect to the destination address \(destinationAddress.string): \(destinationPort)")
                try await self.sendRst(sourceAddress: sourceAddress, sourcePort: sourcePort, destinationAddress: destinationAddress, destinationPort: destinationPort, tcp, .closed)
                return
            }
        }
        else
        {
            /*
             Any other control or text-bearing segment (not containing SYN)
             must have an ACK and thus would be discarded by the ACK
             processing.  An incoming RST segment could not be valid, since
             it could not have been sent in response to anything sent by this
             incarnation of the connection.  So you are unlikely to get here,
             but if you do, drop the segment, and return.
             */
        }
    }

    func addConnection(proxy: TcpProxy, localAddress: IPv4Address, localPort: UInt16, remoteAddress: IPv4Address, remotePort: UInt16, connection: AsyncConnection, irs: SequenceNumber, rcvWnd: UInt16) async throws
    {
        let connection = try await TcpProxyConnection(proxy: proxy, localAddress: localAddress, localPort: localPort, remoteAddress: remoteAddress, remotePort: remotePort, connection: connection, irs: irs, logger: logger, tcpLogger: tcpLogger, rcvWnd: rcvWnd)
        self.connections.append(connection)
    }

    func findConnection(localAddress: IPv4Address, localPort: UInt16, remoteAddress: IPv4Address, remotePort: UInt16, tcp: InternetProtocols.TCP) -> TcpProxyConnection?
    {
        return self.connections.first
        {
            connection in

            return (connection.localAddress  == localAddress ) &&
            (connection.localPort     == localPort    ) &&
            (connection.remoteAddress == remoteAddress) &&
            (connection.remotePort    == remotePort   )
        }
    }

    func removeConnection(_ connection: TcpProxyConnection)
    {
        self.connections.removeAll
        {
            item in

            item == connection
        }
    }

    func sendRst(sourceAddress: IPv4Address, sourcePort: UInt16, destinationAddress: IPv4Address, destinationPort: UInt16, _ tcp: InternetProtocols.TCP, _ state: States) async throws
    {
        switch state
        {
            case .closed:
                /*
                 If the state is CLOSED (i.e., TCB does not exist) then

                 all data in the incoming segment is discarded.  An incoming
                 segment containing a RST is discarded.  An incoming segment not
                 containing a RST causes a RST to be sent in response.  The
                 acknowledgment and sequence field values are selected to make the
                 reset sequence acceptable to the TCP that sent the offending
                 segment.

                 If the ACK bit is off, sequence number zero is used,

                 <SEQ=0><ACK=SEG.SEQ+SEG.LEN><CTL=RST,ACK>

                 If the ACK bit is on,

                 <SEQ=SEG.ACK><CTL=RST>

                 Return.
                 */

                logger.debug("* TCP state is closed")

                if tcp.rst
                {
                    self.logger.debug("* received tcp.reset, doing nothing")
                    return
                }
                else if tcp.ack
                {
                    self.logger.debug("* received tcp.ack, calling send packet with sequenceNumber: tcp.acknowledgementNumber, and ack: true")
                    self.tcpLogger?.debug("(proxy)sendRst() called")
                    try await self.sendPacket(sourceAddress: sourceAddress, sourcePort: sourcePort, destinationAddress: destinationAddress, destinationPort: destinationPort, sequenceNumber: SequenceNumber(tcp.acknowledgementNumber), ack: true)
                }
                else
                {
                    self.logger.debug("* calling send packet with acknowledgement#: tcp.sequenceNumber + TcpProxy.sequenceLength(tcp)")
                    let acknowledgementNumber = SequenceNumber(tcp.sequenceNumber).add(TcpProxy.sequenceLength(tcp))
                    self.tcpLogger?.debug("(proxy)sendRst() called")
                    try await self.sendPacket(sourceAddress: sourceAddress, sourcePort: sourcePort, destinationAddress: destinationAddress, destinationPort: destinationPort, acknowledgementNumber: acknowledgementNumber)
                }
            case .listen:
                self.logger.debug("* TCP state is listen")
                if tcp.ack
                {
                    /*
                     Any acknowledgment is bad if it arrives on a connection still in
                     the LISTEN state.  An acceptable reset segment should be formed
                     for any arriving ACK-bearing segment.  The RST should be
                     formatted as follows:

                     <SEQ=SEG.ACK><CTL=RST>
                     */

                    self.logger.debug("* received tcp.ack, calling send packet with tcp.acknowledgementNumber, and ack: true")

                    self.tcpLogger?.debug("(proxy)sendRst() called")
                    try await self.sendPacket(sourceAddress: sourceAddress, sourcePort: sourcePort, destinationAddress: destinationAddress, destinationPort: destinationPort, sequenceNumber: SequenceNumber(tcp.acknowledgementNumber), ack: true)
                }
                else
                {
                    self.logger.debug("* no tcp.ack received, doing nothing")
                    return
                }

            default:
                self.logger.debug("* TCP state is an unexpected value, doing nothing")
                return
        }
    }

    func sendPacket(sourceAddress: IPv4Address, sourcePort: UInt16, destinationAddress: IPv4Address, destinationPort: UInt16, sequenceNumber: SequenceNumber = SequenceNumber(0), acknowledgementNumber: SequenceNumber = SequenceNumber(0), ack: Bool = false) async throws
    {
        guard let ipv4 = try? IPv4(sourceAddress: sourceAddress, destinationAddress: destinationAddress, sourcePort: sourcePort, destinationPort: destinationPort, sequenceNumber: sequenceNumber, acknowledgementNumber: acknowledgementNumber, syn: false, ack: ack, fin: false, rst: true, windowSize: 0, payload: nil) else
        {
            self.logger.error("* sendPacket() failed to create an IPV4packet")
            throw TcpProxyError.badIpv4Packet
        }

        try await self.client.write(ipv4.data)
    }
}
