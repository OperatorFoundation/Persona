#!/usr/bin/python3

import os

log = open('/root/Persona/udpproxy.log', 'w+')

systemd = os.fdopen(3)
while True:
    lengthBytes = systemd.read(4)
    length = int.from_bytes(lengthBytes, "big")
    data = systemd.read(length)
    address = data[:6]
    payload = data[6:]
    hostBytes = address[:4]
    portBytes = address[4:]
    host = "%d.%d.%d.%d" % (hostBytes[0], hostBytes[1], hostBytes[2], hostBytes[3])
    port = int.from_bytes(portBytes, "big")

    log.write("%s:%d - %d bytes" % (host, port, len(payload)))

if __name__ == '__main__':
    print_hi('PyCharm')

