#!/usr/bin/python3
import sys
from logging import Logger
from tcp import TcpConnection
from systemd import SystemdConnection

class TcpProxy:
    def __init__(self):
        self.running = True

        self.log = Logger('/root/Persona/tcpproxy.log')
        self.log.write("🏀 tcpproxy started 🏀\n")

        self.downstream = SystemdConnection()
        self.upstream = TcpConnection()

        self.connect()

        while self.running:
            self.pump_upstream()
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

            host = "%d.%d.%d.%d" % (host_bytes[0], host_bytes[1], host_bytes[2], host_bytes[3])
            port = int.from_bytes(port_bytes, "big")

            self.log.write("connecting to %s:%d\n" % (host, port))

            self.upstream.connect(host, port)
        except Exception as e:
            try:
                self.log.write("Could not connect: %s" % str(e))
                self.log.flush()

                self.downstreamWrite.write(b'\xF0')  # signal failure to connect
                self.downstreamWrite.flush()

                self.downstream.close()
            finally:
                sys.exit(0)

        try:
            self.log.write("connected\n")

            self.downstreamWrite.write(b'\xF1')  # signal successful connection
            self.downstreamWrite.flush()
        except:
            try:
                self.upstream.close()
                self.downstream.close()
            finally:
                sys.exit(1)

    def pump_downstream(self):
        try:
            payload = self.downstream.readwithlengthprefix()

            self.log.write("persona -> tcpproxy - %d bytes\n" % (len(payload)))

            self.upstream.write(payload)

            self.log.write("tcpproxy -> %s:%d - %d bytes\n" % (self.host, self.port, len(payload)))
        except Exception as e:
            try:
                self.log.write("exception in pumpDownstream: %s" % (str(e)))

                self.running = False

                self.upstream.close()
            finally:
                sys.exit(2)

    def pump_upstream(self):
        try:
            data = self.upstreamConnection.readmaxsize(2048)
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
