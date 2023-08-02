import binascii
import socket
import unittest


class MyTestCase(unittest.TestCase):
    def test_udpproxy(self):
        packet = "00000043450000430b7f4000401138e80a000001a45c47e6a08c0007002fcb35e1939ae1988fe197a2204361746275732069732055445020746f70732120e1939ae1988fe197a2"
        data = binascii.unhexlify(packet)

        conn = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        conn.connect(("146.190.137.108", 1233))
        conn.sendall(data)

        lengthBytes = conn.recv(4)
        length = int.from_bytes(lengthBytes, "big")
        result = conn.recv(length)

        print(result)

        self.assertEqual(data, result)

if __name__ == '__main__':
    unittest.main()
