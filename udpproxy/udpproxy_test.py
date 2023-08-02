import binascii
import socket
import unittest


class MyTestCase(unittest.TestCase):
    def test_udpproxy(self):
        conn = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        conn.connect(("127.0.0.1", 1233))
        conn.sendall(b"\x00\x00\x00\x0a") # length prefix of 10
        conn.sendall(b"\x7f\x00\x00\x01") # 127.0.0.1
        conn.sendall(b"\x00\x07") # 7
        conn.sendall(b"test")

        lengthBytes = conn.recv(4)
        length = int.from_bytes(lengthBytes, "big")
        result = conn.recv(length)
        conn.close()

        print('result:')
        print(binascii.hexlify(result))

        host = result[0:4]
        port = result[4:6]
        payload = result[6:]

        print(binascii.hexlify(host))
        print(binascii.hexlify(port))
        print(payload)

if __name__ == '__main__':
    unittest.main()
