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
        self.downstream = SystemdConnection()

        self.log.write("sockname: %s:%d\n" % (self.upstream.host, self.upstream.port))
        self.log.flush()

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
                return

            host = "%d.%d.%d.%d" % (hostBytes[0], hostBytes[1], hostBytes[2], hostBytes[3])
            port = int.from_bytes(portBytes, "big")

            self.log.write("persona -> udpproxy - %s:%d - %d bytes\n" % (host, port, len(payload)))

            self.upstream.sendto(payload, (host, port))

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
            data, addr = self.upstream.recvfrom(2048)
            (host, port) = addr

            self.log.write("udpproxy <- %s:%d - %d bytes\n" % (host, port, len(data)))

            hostBytes = socket.inet_aton(host)
            portBytes = port.to_bytes(2, "big")

            self.downstream.write(hostBytes)
            self.downstream.write(portBytes)
            self.downstream.writewithlengthprefix(data)

            self.log.write("persona <- udpproxy - %d bytes\n" % (len(dataa)))
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
