//
//  TcpProxyError.swift
//  
//
//  Created by Dr. Brandon Wiley on 3/11/22.
//

import Foundation
import InternetProtocols

public enum TcpProxyError: Error
{
    case addressMismatch(String, String)
    case invalidAddress(Data)
    case notIPv4Packet(Packet)
    case notTcpPacket(Packet)
}
