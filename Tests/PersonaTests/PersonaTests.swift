import XCTest

import Chord
import Logging
import SwiftHexTools
import TransmissionAsync

@testable import Persona

final class PersonaTests: XCTestCase
{
    
    func testUDPProxy()
    {
        print("Starting the UDP Proxy test!")
        let logger = Logger(label: "UDPProxyTestLogger")

        AsyncAwaitThrowingEffectSynchronizer.sync
        {
            print("Attempting to write data...")
            let asyncConnection = try await AsyncTcpSocketConnection("127.0.0.1", 1233, logger)
            let dataString = "00000043450000430b7f4000401138e80a000001a45c47e6a08c0007002fcb35e1939ae1988fe197a2204361746275732069732055445020746f70732120e1939ae1988fe197a2"
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
    
//    func testTaskGroup() async
//    {
//        let string = await withTaskGroup(of: String.self)
//        {
//            group -> String in
//
//            group.addTask
//            {
//                sleep(5)
//                print("Task 1.")
//                return "Hello"
//            }
//
//            group.addTask
//            {
//                print("Task 2.")
//                return "From"
//            }
//
//            group.addTask
//            {
//                print("Task 3.")
//                return "A"
//
//            }
//
//
//            group.addTask
//            {
//                print("Task 4.")
//                return "Task"
//
//            }
//
//            group.addTask
//            {
//                print("Task 5.")
//                return "Group"
//            }
//
//            var collected = [String]()
//
//            for await value in group {
//                collected.append(value)
//            }
//
//            return collected.joined(separator: " ")
//        }
//
//        print(string)
//    }
//
//
//    func testUdpSend() async throws
//    {
//        let queue = BlockingQueue<Bool>()
//        let lock = DispatchSemaphore(value: 0)
//
//        Task
//        {
//            startUdpServer(queue, lock)
//        }
//
//        Task
//        {
//            try await startPersonaServer()
//        }
//
//        Task
//        {
//            startFlowerClient(queue, lock)
//        }
//
//        guard queue.dequeue() else
//        {
//            XCTFail()
//            return
//        }
//    }
//
//    func startUdpServer(_ queue: BlockingQueue<Bool>, _ lock: DispatchSemaphore)
//    {
//        guard let listener = TransmissionListener(port: 1234, type: .udp, logger: nil) else
//        {
//            queue.enqueue(element: false)
//            return
//        }
//
//        while true
//        {
//            let connection = listener.accept()
//            lock.signal()
//
//            Task
//            {
//                handleConnection(connection, queue)
//            }
//        }
//    }
//
//    func handleConnection(_ connection: AsyncConnection, _ queue: BlockingQueue<Bool>)
//    {
//        guard let data = connection.read(size: 9) else
//        {
//            queue.enqueue(element: false)
//            return
//        }
//
//        guard data.string == "helloooo\n" else
//        {
//            queue.enqueue(element: false)
//            return
//        }
//
//        guard connection.write(string: "back") else
//        {
//            queue.enqueue(element: false)
//            return
//        }
//    }
//
//    func startPersonaServer() async throws
//    {
//        let persona = Persona()
//
//        Task
//        {
//            try await persona.run()
//        }
//    }
//
//    func startFlowerClient(_ queue: BlockingQueue<Bool>, _ lock: DispatchSemaphore)
//    {
//        lock.wait()
//
//        let newPacket = "450000258ad100004011ef41c0a801e79fcb9e5adf5104d200115d4268656c6c6f6f6f6f0a"
//
//        guard var pingPacket = Data(hex: newPacket) else
//        {
//            queue.enqueue(element: false)
//            return
//        }
//
//        guard let transmissionConnection: Transmission.Connection = TransmissionConnection(host: "127.0.0.1", port: 1234) else
//        {
//            queue.enqueue(element: false)
//            return
//        }
//
//        let flowerConnection = FlowerConnection(connection: transmissionConnection, log: nil)
//
//        var message = Message.IPRequestV4
//        flowerConnection.writeMessage(message: message)
//
//        guard let ipAssign = flowerConnection.readMessage() else
//        {
//            queue.enqueue(element: false)
//            return
//        }
//
//        switch ipAssign
//        {
//            case .IPAssignV4(let ipv4Address):
//                //                guard let udp = UDP(sourcePort: 4567, destinationPort: 5678, payload: "test".data) else
//                //                {
//                //                    XCTFail()
//                //                    return
//                //                }
//                //
//                //                guard let ipv4 = try? IPv4(sourceAddress: IPv4Address("127.0.0.1")!, destinationAddress: ipv4Address, payload: udp.data, protocolNumber: IPprotocolNumber.UDP) else
//                //                {
//                //                    XCTFail()
//                //                    return
//                //                }
//                //
//                //                let pingPacket = ipv4.data
//
//                let addressData = ipv4Address.rawValue
//                // Some hackery to give the server our assigned IP
//                pingPacket[15] = addressData[3]
//                pingPacket[14] = addressData[2]
//                pingPacket[13] = addressData[1]
//                pingPacket[12] = addressData[0]
//
//                pingPacket[16] = 127
//                pingPacket[17] = 0
//                pingPacket[18] = 0
//                pingPacket[19] = 1
//
//                message = Message.IPDataV4(pingPacket)
//                flowerConnection.writeMessage(message: message)
//
//            default:
//                queue.enqueue(element: false)
//                return
//        }
//
//        guard let receivedMessage = flowerConnection.readMessage() else
//        {
//            queue.enqueue(element: false)
//            return
//        }
//
//        print(receivedMessage)
//
//        switch receivedMessage
//        {
//            case .IPDataV4(let data):
//                let packet = Packet(ipv4Bytes: data, timestamp: Date(), debugPrints: true)
//                print(packet)
//                if let udp = packet.udp
//                {
//                    if let payload = udp.payload
//                    {
//                        print(payload.string)
//
//                        guard payload.string == "back" else
//                        {
//                            queue.enqueue(element: false)
//                            return
//                        }
//
//                        queue.enqueue(element: true)
//                        return
//                    }
//                    else
//                    {
//                        print("No payload")
//                        print(data.hex)
//                        queue.enqueue(element: false)
//                        return
//                    }
//                }
//                else
//                {
//                    print("Not UDP")
//                    queue.enqueue(element: false)
//                    return
//                }
//            default:
//                print("Unknown message \(receivedMessage)")
//                queue.enqueue(element: false)
//                return
//        }
//    }
//
//    func testUpstreamStraw() throws
//    {
//        let upstream = TCPUpstreamStraw(segmentStart: SequenceNumber(0))
//        let segment = try TCP(sourcePort: 1234, destinationPort: 4567, sequenceNumber: SequenceNumber(0), windowSize: 65535, payload: Data(repeating: 0x1A, count: 128))
//        try upstream.write(segment)
//        let result = try upstream.read()
//        XCTAssertEqual(result.data.count, 128)
//    }
//
//    func testDownstreamStraw() throws
//    {
//        let downstream = TCPDownstreamStraw(segmentStart: SequenceNumber(0), windowSize: 65535)
//        let data = Data(repeating: 0x1A, count: 128)
//        try downstream.write(data)
//        let result = try downstream.read()
//        XCTAssertEqual(result.data.count, 128)
//    }
}
