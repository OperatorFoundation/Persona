#!/usr/bin/python3

import os
import socket
import threading

class TcpProxy:
    def __init__(self):
        self.running = True

        self.log = open('/root/Persona/tcpproxy.log', 'w+')
        self.log.write("tcpproxy started\n")
        self.log.flush()

        self.upstream = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

        self.downstreamRead = os.fdopen(3, 'rb')
        self.downstreamWrite = os.fdopen(3, 'wb')

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

        address = self.downstreamRead.read(6)
        hostBytes = address[:4]
        portBytes = address[4:]
        host = "%d.%d.%d.%d" % (hostBytes[0], hostBytes[1], hostBytes[2], hostBytes[3])
        port = int.from_bytes(portBytes, "big")

        self.log.write("connecting to %s:%d\n" % (host, port))
        self.upstream.connect((host, port))
        self.log.write("connected\n")

        while self.running:
            try:
                lengthBytes = self.downstreamRead.read(4)
                length = int.from_bytes(lengthBytes, "big")
                payload = self.downstreamRead.read(length)

                self.log.write("%d bytes\n" % (len(payload)))

                self.upstream.send(payload)
                self.log.write("wrote %d bytes to %s:%d\n" % (len(payload), host, port))
            except:
                self.log.write("exception in pumpUpstream")
                self.running = False
    def pumpDownstream(self):
        self.log.write("pumpDownstream started\n")
        self.log.flush()

        while self.running:
            try:
                self.log.write("reading from upstream\n")
                self.log.flush()

                data = self.upstream.recvfrom(2048)

                self.log.write("received %d bytes from upstream\n" % (len(data)))
                self.log.flush()

                length = len(data)
                lengthBytes = length.to_bytes(4, "big")

                self.log.write("total length %d\n" % (length))
                self.log.flush()

                bs = lengthBytes + data
                self.log.write("writing %d bytes downstream\n" % (len(bs)))
                self.downstreamWrite.write(bs)
                self.log.write("wrote %d bytes downstream\n" % (len(bs)))
            except Exception as e:
                self.log.write("exception in pumpUpstream\n")
                self.log.write("%s\n" % (str(e)))
                self.log.flush()

                self.running = False

if __name__ == '__main__':
    proxy = TcpProxy()
    proxy.wait()