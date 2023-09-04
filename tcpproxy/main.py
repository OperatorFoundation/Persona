#!/usr/bin/python3
import binascii
import os
import socket
import sys
import threading


class StrawException(Exception):
    pass


class Straw:
    def __init__(self):
        self.buffer = b''
        self.count = len(self.buffer)

    def write(self, data):
        self.buffer = self.buffer + data
        self.count = len(self.buffer)

    def readSize(self, size):
        if len(self.buffer) < size:
            raise StrawException()

        result = self.buffer[:size]
        self.buffer = self.buffer[size:]
        self.count = len(self.buffer)

        return result

    def read(self):
        result = self.buffer
        self.buffer = b''
        self.count = len(self.buffer)

        return result


class SystemdConnection:
    def __init__(self, network):
        self.network = network
        self.straw = Straw()

    def readSize(self, size):
        while self.straw.count < size:
            remaining = size - self.straw.count
            next_bytes = self.network.read(remaining)
            self.straw.write(next_bytes)

        return self.straw.readSize(size)

    def readMaxSize(self, maxSize):
        result = self.network.read(maxSize)
        while result == 0:
            result = self.network.read(maxSize)
        return result


class SocketConnection:
    def __init__(self, network):
        self.network = network
        self.straw = Straw()

    def readSize(self, size):
        while self.straw.count < size:
            remaining = size - self.straw.count
            next_bytes = self.network.recv(remaining)
            self.straw.write(next_bytes)

        return self.straw.readSize(size)

    def readMaxSize(self, maxSize):
        result = self.network.recv(maxSize)
        while len(result) == 0:
            result = self.network.recv(maxSize)
        return result


class TcpProxy:
    def __init__(self):
        self.running = True

        self.log = open('/root/Persona/tcpproxy.log', 'w+')
        self.log.write("🏀 tcpproxy started 🏀\n")
        self.log.flush()

        self.upstream = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.upstreamConnection = SocketConnection(self.upstream)

        self.downstreamRead = os.fdopen(3, 'rb')
        self.downstreamReadConnection = SystemdConnection(self.downstreamRead)
        self.downstreamWrite = os.fdopen(3, 'wb')

        self.readBuffer = b''

        self.host = ''
        self.port = 0

        self.upstreamThread = threading.Thread(target=self.pumpUpstream)

        self.pumpDownstream()

        self.upstream.close()
        sys.exit(0)

    def pumpDownstream(self):
#        self.log.write("pumpDownstream started\n")
#        self.log.flush()

#        self.log.write("reading downstream host and port\n")
#        self.log.flush()

        address = self.downstreamReadConnection.readSize(6)

#        self.log.write("read downstream host and port: %d - %s\n" % (len(address), binascii.hexlify(address)))
#        self.log.flush()

        try:
            hostBytes = address[0:4]

#            self.log.write("hostBytes: %d - %s\n" % (len(hostBytes), binascii.hexlify(hostBytes)))
#            self.log.flush()

            portBytes = address[4:6]

#            self.log.write("portBytes: %d - %s\n" % (len(portBytes), binascii.hexlify(portBytes)))
#            self.log.flush()

            host = "%d.%d.%d.%d" % (hostBytes[0], hostBytes[1], hostBytes[2], hostBytes[3])

#            self.log.write("host: %s\n" % str(host))
#            self.log.flush()

            port = int.from_bytes(portBytes, "big")

            self.host = host
            self.port = port

#            self.log.write("port: %d\n" % port)
#            self.log.flush()

            self.log.write("connecting to %s:%d\n" % (host, port))
            self.log.flush()

            self.upstream.connect((host, port))
        except Exception as e:
            self.log.write("Could not connect: %s" % str(e))
            self.log.flush()

            self.downstreamWrite.write(b'\xF0')  # signal failure to connect
            self.downstreamWrite.flush()

            sys.exit(0)

        self.log.write("connected\n")
        self.log.flush()

        self.downstreamWrite.write(b'\xF1')  # signal successful connection
        self.downstreamWrite.flush()

        self.upstreamThread.start()

        while self.running:
            try:
#                self.log.write("reading downstream payload length\n")
#                self.log.flush()

                lengthBytes = self.downstreamReadConnection.readSize(4)

#                self.log.write("read downstream payload bytes: %d - %s\n" % (len(lengthBytes), binascii.hexlify(lengthBytes)))
#                self.log.flush()

                length = int.from_bytes(lengthBytes, "big")

#                self.log.write("length: %d" % length)
#                self.log.flush()

#                self.log.write("reading %d bytes\n" % length)
#                self.log.flush()

                payload = self.downstreamReadConnection.readSize(length)

                self.log.write("persona -> udpproxy - %d bytes\n" % (len(payload)))
                self.log.flush()

#                self.log.write("writing %d bytes to %s:%d\n" % (len(payload), host, port))
#                self.log.flush()

                self.upstream.sendall(payload)

                self.log.write("tcpproxy -> %s:%d - %d bytes\n" % (self.host, self.port, len(payload)))
                self.log.flush()
            except Exception as e:
                self.log.write("exception in pumpDownstream: %s" % (str(e)))
                self.log.flush()

                self.running = False
                return

    def pumpUpstream(self):
#        self.log.write("pumpUpstream started\n")
#        self.log.flush()

        while self.running:
            try:
#                self.log.write("reading from upstream\n")
#                self.log.flush()

                data = self.upstreamConnection.readMaxSize(2048)

                if not data or len(data) == 0:
                    self.log.write("bad upstream read, closing\n")
                    self.log.flush()

                    self.running = False
                    return

                self.log.write("tcpproxy <- %s:%d - %d\n" % (self.host, self.port, len(data)))
                self.log.flush()

                # length = len(data)
                # lengthBytes = length.to_bytes(4, "big")
                #
                # bs = lengthBytes + data

#                self.log.write("client <- tcpproxy - writing %d bytes\n" % (len(bs)))
#                self.log.flush()

                self.downstreamWrite.write(data)
                self.downstreamWrite.flush()

                self.log.write("client <- tcpproxy - %d bytes\n" % (len(data)))
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
