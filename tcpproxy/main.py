#!/usr/bin/python3
import errno
import os
import socket
import sys


class StrawException(Exception):
    pass


class Straw:
    def __init__(self):
        self.buffer = b''
        self.count = len(self.buffer)

    def write(self, data):
        self.buffer = self.buffer + data
        self.count = len(self.buffer)

    def readsize(self, size):
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

    def readsize(self, size):
        while self.straw.count < size:
            remaining = size - self.straw.count
            next_bytes = self.network.read(remaining)
            self.straw.write(next_bytes)

        return self.straw.readsize(size)

    def readmaxsize(self, max_size):
        result = self.network.read(max_size)
        while result == 0:
            result = self.network.read(max_size)
        return result


class SocketConnection:
    def __init__(self, network):
        self.network = network
        self.straw = Straw()

    def readsize(self, size):
        while self.straw.count < size:
            remaining = size - self.straw.count
            next_bytes = self.network.recv(remaining)
            self.straw.write(next_bytes)

        return self.straw.readsize(size)

    def readmaxsize(self, max_size):
        try:
            result = self.network.recv(max_size, socket.MSG_DONTWAIT)
            if result is None:
                return b''
            else:
                return result
        except socket.error as e:
            err = e.args[0]
            if err == errno.EAGAIN or err == errno.EWOULDBLOCK:
                return b''
            else:
                raise e


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

        while self.running:
            self.pump_upstream()
            self.pump_downstream()

        self.log.write("closing and exiting")
        self.log.flush()

        self.upstream.close()
        sys.exit(0)

    def pump_downstream(self):

        address = self.downstreamReadConnection.readsize(6)

        try:
            host_bytes = address[0:4]
            port_bytes = address[4:6]

            host = "%d.%d.%d.%d" % (host_bytes[0], host_bytes[1], host_bytes[2], host_bytes[3])
            port = int.from_bytes(port_bytes, "big")

            self.host = host
            self.port = port

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

        try:

            length_bytes = self.downstreamReadConnection.readsize(4)
            length = int.from_bytes(length_bytes, "big")
            payload = self.downstreamReadConnection.readsize(length)

            self.log.write("persona -> tcpproxy - %d bytes\n" % (len(payload)))
            self.log.flush()

            self.upstream.sendall(payload)

            self.log.write("tcpproxy -> %s:%d - %d bytes\n" % (self.host, self.port, len(payload)))
            self.log.flush()
        except Exception as e:
            self.log.write("exception in pumpDownstream: %s" % (str(e)))
            self.log.flush()

            self.running = False

    def pump_upstream(self):

        try:
            data = self.upstreamConnection.readmaxsize(2048)
            if data is None:
                self.log.write("No Data")
                self.log.flush()

            self.log.write("tcpproxy <- %s:%d - %d\n" % (self.host, self.port, len(data)))
            self.log.flush()

            length = len(data)
            length_bytes = length.to_bytes(4, "big")

            bs = length_bytes + data

            self.log.write("client <- tcpproxy - writing %d bytes\n" % (len(bs)))
            self.log.flush()

            self.downstreamWrite.write(bs)
            self.downstreamWrite.flush()

            self.log.write("client <- tcpproxy - %d bytes\n" % (len(data)))
            self.log.flush()

        except Exception as e:
            self.log.write("exception in pumpUpstream\n")
            self.log.flush()

            self.log.write("%s\n" % (str(e)))
            self.log.flush()

            self.running = False


if __name__ == '__main__':
    proxy = TcpProxy()
