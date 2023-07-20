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
    public init(string: String)
    {
        self.init(string)! // FIXME - dangerous
    }
}
