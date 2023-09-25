//
//  TcpIdentity.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/5/23.
//

import Foundation

import Foundation

import InternetProtocols
import Net

public struct TcpIdentity
{
    public let localAddress: IPv4Address
    public let localPort: UInt16
    public let remoteAddress: IPv4Address
    public let remotePort: UInt16

    public init(ipv4: IPv4, tcp: TCP) throws
    {
        guard let localAddress = IPv4Address(data: ipv4.sourceAddress) else
        {
            throw UdpProxyError.dataConversionFailed
        }

        guard let remoteAddress = IPv4Address(data: ipv4.destinationAddress) else
        {
            throw UdpProxyError.dataConversionFailed
        }

        self.init(localAddress: localAddress, localPort: tcp.sourcePort, remoteAddress: remoteAddress, remotePort: tcp.destinationPort)
    }

    public init(localAddress: IPv4Address, localPort: UInt16, remoteAddress: IPv4Address, remotePort: UInt16)
    {
        self.localAddress = localAddress
        self.localPort = localPort
        self.remoteAddress = remoteAddress
        self.remotePort = remotePort
    }

    public init(data: Data) throws
    {
        guard data.count == 12 else
        {
            throw TcpIdentityError.badIdentity
        }

        let localAdddressBytes = Data(data[0..<4])
        let localPortBytes = Data(data[4..<6])
        let remoteAdddressBytes = Data(data[6..<10])
        let remotePortBytes = Data(data[10..<12])

        guard let localAddress = IPv4Address(data: localAdddressBytes) else
        {
            throw TcpIdentityError.badIdentity
        }
        guard let localPort = localPortBytes.maybeNetworkUint16 else
        {
            throw TcpIdentityError.badIdentity
        }
        guard let remoteAddress = IPv4Address(data: remoteAdddressBytes) else
        {
            throw TcpIdentityError.badIdentity
        }
        guard let remotePort = remotePortBytes.maybeNetworkUint16 else
        {
            throw TcpIdentityError.badIdentity
        }

        self.init(localAddress: localAddress, localPort: localPort, remoteAddress: remoteAddress, remotePort: remotePort)
    }
}

extension TcpIdentity: Equatable
{
    static public func ==(lhs: TcpIdentity, rhs: TcpIdentity) -> Bool
    {
        return (lhs.localAddress == rhs.localAddress) && (lhs.localPort == rhs.localPort) && (lhs.remoteAddress == rhs.remoteAddress) && (lhs.remotePort == rhs.remotePort)
    }
}

extension TcpIdentity: Hashable
{
    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(self.localAddress)
        hasher.combine(self.localPort)
        hasher.combine(self.remoteAddress)
        hasher.combine(self.remotePort)
    }
}

public enum TcpIdentityError: Error
{
    case badIdentity
}
