class Logger:
    def __init__(self, path):
        self.log = open(path, 'w+')
    def write(self, message):
        self.log.write(message)
        self.log.flush()
