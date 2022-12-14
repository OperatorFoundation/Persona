//
//  States.swift
//  
//
//  Created by Dr. Brandon Wiley on 12/13/22.
//

import Foundation

public enum States
{
    case listen
    case synSent
    case synReceived
    case established
    case finWait1
    case finWait2
    case closeWait
    case closing
    case lastAck
    case timeWait
    case closed
}
