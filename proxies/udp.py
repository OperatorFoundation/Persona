import errno
import socket

class UdpConnection:
    def __init__(self):
        self.network = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.network.bind(('0.0.0.0', 0))
        (self.host, self.port) = self.network.getsockname()

    def read(self):
        try:
            (data, addr) = self.network.recvfrom(2048, socket.MSG_DONTWAIT)
            (host, port) = addr
            return host, port, data
        except socket.error as e:
            err = e.args[0]
            if err == errno.EAGAIN or err == errno.EWOULDBLOCK:
                return "0.0.0.0", 0, b''
            else:
                raise e

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