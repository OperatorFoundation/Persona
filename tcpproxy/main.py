#!/usr/bin/python3
import binascii
import os
import socket
import sys
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

        self.downstreamThread = threading.Thread(target=self.pumpDownstream)

        self.pumpUpstream()

        self.upstream.close()
        sys.exit(0)

    def pumpUpstream(self):
        self.log.write("pumpUpstream started\n")
        self.log.flush()

        self.log.write("reading upstream host and port\n")

        address = self.downstreamRead.read(6)

        self.log.write("read upstream host and port: %d - %s\n" % (len(address), binascii.hexlify(address)))

        hostBytes = address[0:4]
        portBytes = address[4:6]
        host = socket.inet_aton(hostBytes)
        port = int.from_bytes(portBytes, "big")

        self.log.write("connecting to %s:%d\n" % (host, port))
        self.log.flush()

        try:
            self.upstream.connect((host, port))
        except Exception as e:
            self.log.write("Could not connect to %s:%d - %s" % (host, port, str(e)))
            self.log.flush()

            self.downstreamWrite.write(b'\xF0') # signal failure to connect
            self.downstreamWrite.flush()
            sys.exit(0)

        self.log.write("connected\n")
        self.log.flush()

        self.downstreamWrite.write(b'\xF1') # signal successful connection
        self.downstreamWrite.flush()

        self.downstreamThread.start()

        while self.running:
            try:
                self.log.write("reading upstream payload length\n")
                self.log.flush()

                lengthBytes = self.downstreamRead.read(4)

                self.log.write("read upstream payload bytes: %d - %s\n" % (len(lengthBytes), binascii.hexlify(lengthBytes)))
                self.log.flush()

                length = int.from_bytes(lengthBytes, "big")

                self.log.write("length: %d" % length)
                self.log.flush()

                self.log.write("reading %d bytes\n" % length)

                payload = self.downstreamRead.read(length)

                self.log.write("read %d bytes\n" % (len(payload)))
                self.log.flush()

                self.log.write("writing %d bytes to %s:%d\n" % (len(payload), host, port))
                self.log.flush()

                self.upstream.sendall(payload)

                self.log.write("wrote %d bytes to %s:%d\n" % (len(payload), host, port))
                self.log.flush()
            except Exception as e:
                self.log.write("exception in pumpUpstream: %s" % (str(e)))
                self.log.flush()

                self.running = False
                return

    def pumpDownstream(self):
        self.log.write("pumpDownstream started\n")
        self.log.flush()

        while self.running:
            try:
                self.log.write("reading from upstream\n")
                self.log.flush()

                data = self.upstream.recv(2048)

                if not data or len(data) == 0:
                    self.log.write("bad upstream read, closing\n")
                    self.log.flush()

                    self.running = False
                    return

                self.log.write("read %d - %s from upstream\n" % (len(data), binascii.hexlify(data)))
                self.log.flush()

                length = len(data)
                lengthBytes = length.to_bytes(4, "big")

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
                return

if __name__ == '__main__':
    proxy = TcpProxy()
