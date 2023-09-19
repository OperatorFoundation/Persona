import errno
import socket

class UdpConnection:
    def __init__(self):
        self.network = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.network.bind(('0.0.0.0', 0))
        (self.host, self.port) = self.network.getsockname()

    def read(self):
        result = self.network.recvfrom(2048, socket.MSG_DONTWAIT)
        if result:
            (data, addr) = result
            (host, port) = addr
            return host, port, data
        else:
            return b'\x00\x00\x00\x00', 0, b''

    def write(self, host, port, data):
        try:
            self.network.sendto(data, (host, port))
        except socket.error as e:
            err = e.args[0]
            if err == errno.EAGAIN or err == errno.EWOULDBLOCK:
                return self.write(host, port, data)
            else:
                raise e

    def close(self):
        try:
            self.network.close()
        except:
            pass