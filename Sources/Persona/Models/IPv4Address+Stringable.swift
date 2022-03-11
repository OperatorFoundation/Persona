//
//  IPv4Address+Stringable.swift
//  
//
//  Created by Dr. Brandon Wiley on 3/7/22.
//

import Datable
import Foundation
import Net

extension IPv4Address: Stringable
{
    public var string: String
    {
        let data = self.rawValue
        return "\(data[0]).\(data[1]).\(data[2]).\(data[3])"
    }

    public init(string: String)
    {
        self.init(string)! // FIXME - dangerous
    }
}
