class Straw:
    def __init__(self):
        self.buffer = b''
        self.count = len(self.buffer)

    def write(self, data):
        self.buffer = self.buffer + data
        self.count = len(self.buffer)

    def readsize(self, size):
        if len(self.buffer) < size:
            raise StrawException()

        result = self.buffer[:size]
        self.buffer = self.buffer[size:]
        self.count = len(self.buffer)

        return result

    def read(self):
        result = self.buffer
        self.buffer = b''
        self.count = len(self.buffer)

        return result

class StrawException(Exception):
    pass
