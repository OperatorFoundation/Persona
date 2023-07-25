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

        self.upstream = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.upstream.bind(('0.0.0.0', 0))
        (self.host, self.port) = self.upstream.getsockname()
        self.log.write("sockname: %s:%d\n" % (self.host, self.port))
        self.log.flush()

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
        self.log.flush()

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
                self.log.write("wrote %d bytes to %s:%d\n" % (len(payload), host, port))
            except:
                self.log.write("exception in pumpUpstream")
                self.running = False
    def pumpDownstream(self):
        self.log.write("pumpDownstream started\n")
        self.log.flush()

        while self.running:
            try:
                self.log.write("reading from %s:%d\n" % (self.host, self.port))
                self.log.flush()

                data, addr = self.upstream.recvfrom(2048)
                (host, port) = addr

                self.log.write("received %d bytes from upstream %s:%d\n" % (len(data), host, port))
                self.log.flush()

                length = len(data) + 6
                lengthBytes = length.to_bytes(4, "big")

                self.log.write("total length %d\n" % (length))
                self.log.flush()

                parts = host.split(".")
                self.log.write("host to bytes %s %d\n" % (host, len(parts)))
                self.log.flush()

                hostBytes = chr(int(parts[0])) + chr(int(parts[1])) + chr(int(parts[2])) + chr(int(parts[3]))

                self.log.write("hostBytes %d\n" % (len(hostBytes)))
                self.log.flush()

                self.log.write("port: %d" % (port))
                self.log.flush()

                portBytes = port.to_bytes(2, "big")

                self.log.write("portBytes" % (len(portBytes)))
                self.log.flush()

                bytes = lengthBytes + hostBytes + portBytes + data
                self.downstream.write(bytes)
                self.log.write("wrote %d bytes downstream" % (len(bytes)))
            except Exception as e:
                self.log.write("exception in pumpUpstream\n")
                self.log.write("%s\n" % (str(e)))
                self.log.flush()

                self.running = False

if __name__ == '__main__':
    proxy = UdpProxy()
    proxy.wait()