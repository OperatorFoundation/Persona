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
        portBytes = address[4:6]
        host = socket.inet_aton(hostBytes)
        port = int.from_bytes(portBytes, "big")

        self.log.write("connecting to %s:%d\n" % (host, port))
        self.log.flush()

        self.upstream.connect((host, port))

        self.log.write("connected\n")
        self.log.flush()

        while self.running:
            try:
                lengthBytes = self.downstreamRead.read(4)
                length = int.from_bytes(lengthBytes, "big")
                payload = self.downstreamRead.read(length)

                self.log.write("%d bytes\n" % (len(payload)))
                self.log.flush()

                self.upstream.send(payload)

                self.log.write("wrote %d bytes to %s:%d\n" % (len(payload), host, port))
                self.log.flush()
            except:
                self.log.write("exception in pumpUpstream")
                self.log.flush()

                self.running = False
    def pumpDownstream(self):
        self.log.write("pumpDownstream started\n")
        self.log.flush()

        while self.running:
            try:
                self.log.write("reading from upstream\n")
                self.log.flush()

                data = self.upstream.recv(2048)

                if len(data) == 0:
                    self.running = False
                    break

                self.log.write("received %d bytes from upstream\n" % (len(data)))
                self.log.flush()

                length = len(data)
                lengthBytes = length.to_bytes(4, "big")

                self.log.write("total length %d\n" % (length))
                self.log.flush()

                bs = lengthBytes + data

                self.log.write("writing %d bytes downstream\n" % (len(bs)))
                self.log.flush()

                self.downstreamWrite.write(bs)
                self.downstreamWrite.flush()

                self.log.write("wrote %d bytes downstream\n" % (len(bs)))
                self.log.flush()

            except Exception as e:
                self.log.write("exception in pumpUpstream\n")
                self.log.flush()
                
                self.log.write("%s\n" % (str(e)))
                self.log.flush()

                self.running = False
                break

if __name__ == '__main__':
    proxy = TcpProxy()
    proxy.wait()