//
//  AddressPool.swift
//  ReplicantSwiftServerCore
//
//  Created by Dr. Brandon Wiley on 1/29/19.
//

import Foundation

struct AddressPool
{
    let base: String = "10.8.0."
    var used: [Bool] = [Bool](repeating: false, count: 256)

    init()
    {
        // Reserved
        used[0] = true
        used[1] = true
        used[255] = true
    }

    mutating func allocate() -> String?
    {
        guard let index = used.firstIndex(of: false) else
        {
            print("allocate failed in AddressPool")
            return nil
        }

        used[index] = true

        return base + index.string
    }

    mutating func deallocate(address: String)
    {
        let stringIndex = address.split(separator: ".")[3]

        guard let index = Int(stringIndex) else
        {
            print("deallocate failed in AddressPool")
            return
        }

        used[index]=false
    }
}
