//
//  ConduitCollection.swift
//  ReplicantSwiftServer
//
//  Created by Adelita Schule on 11/29/18.
//

import Foundation
import Flower

public class ConduitCollection: NSObject
{
    private var conduits: [String : Conduit] = [ : ]

    func addConduit(address: String, flowerConnection: FlowerConnection)
    {
        print("\n* Adding a conduit to the conduit collection.")
        let newConduit = Conduit(address: address, flowerConnection: flowerConnection)

        conduits[address] = newConduit
    }

    func removeConduit(with address: String)
    {
        print("* Removing a conduit from the conduit collection.")
        conduits.removeValue(forKey: address)
    }

    func getConduit(with address: String) -> Conduit?
    {
        print("* Getting conduit with address \(address)")
        if let conduit = conduits[address]
        {
            return conduit
        }
        else
        {
            return nil
        }
    }
}
