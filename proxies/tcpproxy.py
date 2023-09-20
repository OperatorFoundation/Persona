#!/usr/bin/python3
import binascii
import sys
from enum import Enum
from logging import Logger
from tcp import TcpConnection
from systemd import SystemdConnection

class TcpProxyMessage(Enum):
    upstreamOnly   = 1
    downstreamOnly = 2
    bidirectional  = 3
    close          = 4

    @classmethod
    def new(self, data):
        return TcpProxyMessage(data[0])

    def data(self):
        return bytes(chr(self.value))

class TcpProxy:
    def __init__(self):
        self.running = True

        self.log = Logger('/root/Persona/tcpproxy.log')
        self.log.write("🏀 tcpproxy started 🏀\n")

        self.downstream = SystemdConnection(self.log)
        self.upstream = TcpConnection()

        self.host = b''
        self.port = 0

        self.connect()

        while self.running:
            self.pump_downstream()

        self.log.write("closing and exiting")

        self.upstream.close()
        self.downstream.close()
        sys.exit(0)

    def connect(self):
        address = self.downstream.readsize(6)

        try:
            host_bytes = address[0:4]
            port_bytes = address[4:6]

            self.host = "%d.%d.%d.%d" % (host_bytes[0], host_bytes[1], host_bytes[2], host_bytes[3])
            self.port = int.from_bytes(port_bytes, "big")

            self.log.write("connecting to %s:%d\n" % (self.host, self.port))

            self.upstream.connect(self.host, self.port)
        except Exception as e:
            try:
                self.log.write("Could not connect: %s" % str(e))

                self.downstream.write(b'\xF0')  # signal failure to connect
                self.downstream.close()
            finally:
                sys.exit(0)

        try:
            self.log.write("connected\n")

            self.downstream.write(b'\xF1')  # signal successful connection
        except:
            try:
                self.upstream.close()
                self.downstream.close()
            finally:
                sys.exit(1)

    def pump_downstream(self):
        try:
            messageBytes = self.downstream.readsize(1)
            message = TcpProxyMessage.new(messageBytes)

            print("persona -> ", message)

            if message == TcpProxyMessage.upstreamOnly or message == TcpProxyMessage.bidirectional:
                payload = self.downstream.readwithlengthprefix()

                self.log.write("persona -> tcpproxy - %d bytes\n" % (len(payload)))

                self.upstream.write(payload)

                self.log.write("tcpproxy -> %s:%d - %d bytes\n" % (self.host, self.port, len(payload)))

            if message == TcpProxyMessage.downstreamOnly or message == TcpProxyMessage.bidirectional:
                self.pump_downstream()

            if message == TcpProxyMessage.close:
                self.log.write("Close message received, exiting")
                self.upstream.close()
                self.downstream.close()
                sys.exit(0)
        except Exception as e:
            try:
                self.log.write("exception in pumpDownstream: %s" % (str(e)))

                self.running = False

                self.upstream.close()
            finally:
                sys.exit(2)

    def pump_upstream(self):
        try:
            data = self.upstream.readmaxsize(2048)
            if data is None:
                self.log.write("No Data")

            self.log.write("tcpproxy <- %s:%d - %d\n" % (self.host, self.port, len(data)))

            self.downstream.writewithlengthprefix(data)

            self.log.write("persona <- tcpproxy - %d bytes\n" % (len(data)))

        except Exception as e:
            try:
                self.log.write("exception in pumpUpstream\n")

                self.log.write("%s\n" % (str(e)))

                self.running = False

                self.upstream.close()
                self.downstream.close()
            finally:
                sys.exit(3)

if __name__ == '__main__':
    proxy = TcpProxy()
