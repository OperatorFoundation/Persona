//
//  NWEndpoint+Host+Stringable.swift
//  
//
//  Created by Dr. Brandon Wiley on 3/7/22.
//

import Datable
import Foundation
import Net

extension NWEndpoint.Host: Stringable
{
    public var string: String
    {
        switch self
        {
            case .ipv4(let ipv4):
                return ipv4.string
            case .ipv6(_):
                return "IPv6"
            case .name(let name, _):
                return name
            default:
                return "[Unknown Address Type]"
        }
    }

    public init(string: String)
    {
        self.init(string)
    }
}
