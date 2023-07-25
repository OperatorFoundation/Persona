#!/usr/bin/python3

import os
import socket
import threading

class UdpProxy:
    def __init__(self):
        self.running = True

        self.log = open('/root/Persona/udpproxy.log', 'w+')
        self.log.write("udpproxy started\n")
        self.log.flush()

        print("udpproxy started\n")

        self.upstream = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.upstream.bind(('0.0.0.0', 0))

        self.downstream = os.fdopen(3, 'rb')

        self.thread1 = threading.Thread(target=self.pumpUpstream)
        self.thread2 = threading.Thread(target=self.pumpDownstream)
        self.thread1.start()
        self.thread2.start()

    def wait(self):
        self.thread1.join()
        self.thread2.join()

    def pumpUpstream(self):
        self.log.write("pumpUpstream started\n")
        while self.running:
            try:
                lengthBytes = self.downstream.read(4)
                length = int.from_bytes(lengthBytes, "big")
                data = self.downstream.read(length)

                if length < 6:
                    self.running = False
                    break

                if len(data) != length:
                    self.running = False
                    break

                address = data[:6]
                payload = data[6:]
                hostBytes = address[:4]
                portBytes = address[4:]
                host = "%d.%d.%d.%d" % (hostBytes[0], hostBytes[1], hostBytes[2], hostBytes[3])
                port = int.from_bytes(portBytes, "big")

                self.log.write("%s:%d - %d bytes\n" % (host, port, len(payload)))

                self.upstream.sendto(payload, (host, port))
            except:
                self.log.write("exception in pumpUpstream")
                self.running = False
    def pumpDownstream(self):
        self.log.write("pumpDownstream started\n")
        while self.running:
            try:
                data, addr = self.upstream.recvfrom(2048)
                length = len(data) + 6
                lengthBytes = length.to_bytes(4, "big")
                (host, port) = addr
                parts = host.split(".")
                hostBytes = chr(parts[0]) + chr(parts[1]) + chr(parts[2]) + chr(parts[3])
                portBytes = port.to_bytes("big")
                bytes = lengthBytes + hostBytes + portBytes + data
                self.downstream.write(bytes)
            except:
                self.log.write("exception in pumpUpstream")
                self.running = False

if __name__ == '__main__':
    print("__main__")
    proxy = UdpProxy()
    print("waiting...")
    proxy.wait()
    print("exiting!")
