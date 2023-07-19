# Update
git pull origin main
swift build

# Run UDP echo server
swift run UdpEchoServer run &
echo "$!" >udpecho.pid

# Run TCP echo server
swift run TcpEchoServer run &
echo "$!" >tcpecho.pid

# Run Persona
swift run Persona run

# Kill UDP echo server and TCP echo server
kill `cat udpecho.pid`
kill -9 `cat udpecho.pid`
kill `cat tcpecho.pid`
kill -9 `cat tcpecho.pid`
rm udpecho.pid
rm tcpecho.pid

