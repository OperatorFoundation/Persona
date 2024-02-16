import XCTest

import Chord
import Logging
import SwiftHexTools
import TransmissionAsync

@testable import Persona

final class PersonaTests: XCTestCase
{
    func testUDPProxy() async throws
    {
        print("Starting the UDP Proxy test!")
        let logger = Logger(label: "UDPProxyTestLogger")

        print("Attempting to write data...")
        let asyncConnection = try await AsyncTcpSocketConnection("", 1233, logger, verbose: true)
        let dataString = "0000000a7f000001000774657374"
        guard let data = Data(hex: dataString) else
        {
            XCTFail()
            return
        }

        try await asyncConnection.write(data)

        print("Wrote \(data.count) bytes, attempting to read some data...")
        let responseData = try await asyncConnection.readWithLengthPrefix(prefixSizeInBits: 32)

        print("Received \(responseData.count) bytes of response data: \n\(responseData.hex)")
    }
}
