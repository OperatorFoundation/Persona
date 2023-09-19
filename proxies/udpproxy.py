#!/usr/bin/python3
import sys
import socket
from logging import Logger
from systemd import SystemdConnection
from udp import UdpConnection

class UdpProxy:
    def __init__(self):
        self.running = True

        self.log = Logger('/root/Persona/udpproxy.log')
        self.log.write("udpproxy started\n")

        self.upstream = UdpConnection()
        self.downstream = SystemdConnection(self.log)

        self.log.write("sockname: %s:%d\n" % (self.upstream.host, self.upstream.port))

        while self.running:
            self.pump_upstream()
            self.pump_downstream()

        self.log.write("closing and exiting")

        self.upstream.close()
        self.downstream.close()
        sys.exit(0)

    # The format to talk to service is a 4 byte length, following by that many bytes.
    # Included in those bytes are a 4 byte host, a 2 byte port, and the then variable length payload.
    def pump_upstream(self):
        try:
            hostBytes = self.downstream.readsize(4)
            portBytes = self.downstream.readsize(2)

            payload = self.downstream.readwithlengthprefix()

            if len(payload) == 0:
                self.log.write("persona -> udpproxy - 0 bytes\n")
                return

            host = "%d.%d.%d.%d" % (hostBytes[0], hostBytes[1], hostBytes[2], hostBytes[3])
            port = int.from_bytes(portBytes, "big")

            self.log.write("persona -> udpproxy - %s:%d - %d bytes\n" % (host, port, len(payload)))

            self.upstream.write(host, port, payload)

            self.log.write("udpproxy -> %s:%d - %d bytes\n" % (host, port, len(payload)))
        except Exception as e:
            self.log.write("exception in pumpUpstream %s" % str(e))
            self.running = False
            try:
                self.upstream.close()
                self.downstream.close()
            finally:
                sys.exit(1)

    def pump_downstream(self):
        try:
            host, port, data = self.upstream.read()

            self.log.write("udpproxy <- %s:%d - %d bytes\n" % (host, port, len(data)))

            hostBytes = socket.inet_aton(host)
            portBytes = port.to_bytes(2, "big")

            self.log.write("write hostBytes\n")
            self.downstream.write(hostBytes)
            self.log.write("write portBytes\n")
            self.downstream.write(portBytes)
            self.log.write("write with length prefix %d\n" % len(data))
            self.downstream.writewithlengthprefix(data)

            self.log.write("persona <- udpproxy - %d bytes\n" % (len(data)))
        except Exception as e:
            self.log.write("exception in pumpUpstream\n")
            self.log.write("%s\n" % (str(e)))

            self.running = False
            try:
                self.upstream.close()
                self.downstream.close()
            finally:
                sys.exit(2)

if __name__ == '__main__':
    proxy = UdpProxy()
