//
//  EndpointV4.swift
//  
//
//  Created by Dr. Brandon Wiley on 7/20/23.
//

import Crypto
import Foundation

import Datable
import KeychainCli
import Net

public struct EndpointV4: MaybeDatable, Hashable, Comparable, Codable
{
    public let host: IPv4Address
    public let port: NWEndpoint.Port

    public var data: Data
    {
        var result = Data()
        result.append(port.data)
        result.append(host.data)
        return result
    }

    public init(host: IPv4Address, port: NWEndpoint.Port)
    {
        self.host = host
        self.port = port
    }

    public init?(data: Data)
    {
        guard let (portData, tail) = data.splitOn(position: 2) else
        {
            return nil
        }

        let p = NWEndpoint.Port(integerLiteral: portData.uint16!)

        port = p

        guard let address = IPv4Address.init(tail) else
        {
            return nil
        }

        host = address
    }

    public static func < (lhs: EndpointV4, rhs: EndpointV4) -> Bool
    {
        if lhs.host.rawValue.lexicographicallyPrecedes(rhs.host.rawValue)
        {
            return true
        }
        else if rhs.host.rawValue.lexicographicallyPrecedes(lhs.host.rawValue)
        {
            return false
        }
        else
        {
            return lhs.port.rawValue < rhs.port.rawValue
        }
    }
}

public func generateStreamID(source: EndpointV4, destination: EndpointV4) -> UInt64
{
    var sha512 = SHA512()

    if (source < destination)
    {
        sha512.update(data: source.data)
        sha512.update(data: destination.data)
    }
    else
    {
        sha512.update(data: destination.data)
        sha512.update(data: source.data)
    }

    let hashValue = sha512.finalize()
    let hashData = Data(hashValue)
    let firstEight = Data(hashData[..<8])

    // Force unwrap performed under duress
    return firstEight.maybeNetworkUint64!
}
