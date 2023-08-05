//
//  UdpIdentity.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/5/23.
//

import Foundation

import InternetProtocols
import Net

public struct UdpIdentity
{
    public let localAddress: IPv4Address
    public let localPort: UInt16

    public init(ipv4: IPv4, udp: UDP) throws
    {
        guard let address = IPv4Address(data: ipv4.sourceAddress) else
        {
            throw UdpProxyError.dataConversionFailed
        }

        self.init(localAddress: address, localPort: udp.sourcePort)
    }

    public init(localAddress: IPv4Address, localPort: UInt16)
    {
        self.localAddress = localAddress
        self.localPort = localPort
    }
}

extension UdpIdentity: Equatable
{
    static public func ==(lhs: UdpIdentity, rhs: UdpIdentity) -> Bool
    {
        return (lhs.localAddress == rhs.localAddress) && (lhs.localPort == rhs.localPort)
    }
}

extension UdpIdentity: Hashable
{
    public func hash(into hasher: inout Hasher)
    {
        hasher.combine(self.localAddress)
        hasher.combine(self.localPort)
    }
}
