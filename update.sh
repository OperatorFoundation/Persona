git pull origin main

swift package reset
rm -rf .build >/dev/null
rm -rf .swiftpm >/dev/null
rm -rf Package.resolved >/dev/null

swift package update
swift build -c release

pushd frontend
go get frontend
go install
popd

systemctl stop frontend.socket
systemctl stop persona.socket
systemctl stop udpproxy.socket >/dev/null 2>/dev/null
systemctl stop tcpproxy.socket >/dev/null 2>/dev/null

killall tcpproxy.py >/dev/null 2>/dev/null
killall -9 tcpproxy.py >/dev/null 2>/dev/null

killall udpproxy.py >/dev/null 2>/dev/null
killall -9 udpproxy.py >/dev/null 2>/dev/null

killall Persona >/dev/null 2>/dev/null
killall -9 Persona >/dev/null 2>/dev/null

killall frontend >/dev/null 2>/dev/null
killall -9 frontend >/dev/null 2>/dev/null

systemctl start persona.socket
systemctl start frontend.socket
