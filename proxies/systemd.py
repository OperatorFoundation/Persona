class SystemdConnection:
    def __init__(self):
        self.straw = Straw()

        self.downstreamRead = os.fdopen(3, 'rb')
        self.downstreamWrite = os.fdopen(3, 'wb')

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

    def readwithlengthprefix(self):
        length_bytes = self.network.readsize(4)
        length = int.from_bytes(length_bytes, "big")
        payload = self.network.readsize(length)
        return payload

    def write(self, data):
        self.downstreamWrite.write(data)
        self.downstreamWrite.flush()

    def writewithlengthprefix(self, data):
        length = len(data)
        length_bytes = length.to_bytes(4, "big")

        bs = length_bytes + data

        self.network.write(bs)

    def close(self):
        try:
            self.downstreamRead.close()
        except:
            pass