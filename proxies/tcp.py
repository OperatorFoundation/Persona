from straw import Straw

class TcpConnection:
    def __init__(self):
        self.network = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.straw = Straw()

    def connect(self, host, port):
        self.network.connect((host, port))

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

    def write(self, data):
        try:
            self.network.sendall(data)
            self.network.flush()
        except socket.error as e:
            err = e.args[0]
            if err == errno.EAGAIN or err == errno.EWOULDBLOCK:
                return self.write(data)
            else:
                raise e

    def close(self):
        try:
            self.network.close()
        except:
            pass