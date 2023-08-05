//
//  Data+IPv4AddressString.swift
//  
//
//  Created by Dr. Brandon Wiley on 8/5/23.
//

import Foundation

// Swift surprisingly has no easy way to convert IPv4 addresses between Data and String.
// This extension provides that functionality as an extension on Data.

extension Data
{
    public var ipv4AddressString: String?
    {
        guard self.count == 4 else
        {
            return nil
        }

        return "\(self[0]).\(self[1]).\(self[2]).\(self[3])"
    }
}
