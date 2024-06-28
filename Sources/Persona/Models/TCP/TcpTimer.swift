////
////  TcpTimer.swift
////  
////
////  Created by Dr. Brandon Wiley on 6/28/24.
////
//
//import Logging
//import Foundation
//
//import Chord
//import Datable
//import InternetProtocols
//import Net
//import Puppy
//import TransmissionAsync
//
//public struct TcpProxyRequest: CustomStringConvertible
//{
//    public var description: String
//    {
//        if let payload = self.payload
//        {
//            return "[TCP Request \(self.type): \(self.identity), \(payload.count) bytes]"
//        }
//        else
//        {
//            return "[TCP Request \(self.type): \(self.identity)]"
//        }
//    }
//
//    public var data: Data
//    {
//        let typeBytes = Data(array: [Subsystem.Tcpproxy.rawValue, self.type.rawValue])
//        let identityBytes = self.identity.data
//
//        if let payload = self.payload
//        {
//            return typeBytes + identityBytes + payload
//        }
//        else
//        {
//            return typeBytes + identityBytes
//        }
//    }
//
//    let type: TcpProxyRequestType
//    let identity: Identity
//    let payload: Data?
//
//    public init(type: TcpProxyRequestType, identity: Identity, payload: Data? = nil)
//    {
//        self.type = type
//        self.identity = identity
//        self.payload = payload
//    }
//}
