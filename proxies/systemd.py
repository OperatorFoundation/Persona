import os
from straw import Straw

class SystemdConnection:
    def __init__(self, log):
        self.log = log

        self.straw = Straw()

        self.downstreamRead = os.fdopen(3, 'rb')
        self.downstreamWrite = os.fdopen(3, 'wb')

    def readsize(self, size):
        while self.straw.count < size:
            remaining = size - self.straw.count
            next_bytes = self.downstreamRead.read(remaining)
            self.straw.write(next_bytes)

        return self.straw.readsize(size)

    def readmaxsize(self, max_size):
        result = self.downstreamRead.read(max_size)
        while result == 0:
            result = self.downstreamRead.read(max_size)
        return result

    def readwithlengthprefix(self):
        length_bytes = self.readsize(4)
        length = int.from_bytes(length_bytes, "big")
        payload = self.readsize(length)
        return payload

    def write(self, data):
        self.log.write("writing downstream %d bytes" % len(data))
        self.downstreamWrite.write(data)
        self.downstreamWrite.flush()

    def writewithlengthprefix(self, data):
        length = len(data)
        length_bytes = length.to_bytes(4, "big")

        bs = length_bytes + data

        self.downstreamWrite.write(bs)

    def close(self):
        try:
            self.downstreamRead.close()
        except:
            pass