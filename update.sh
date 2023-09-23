git pull origin main

swift package reset
rm -rf .build >/dev/null
rm -rf .swiftpm >/dev/null
rm -rf Package.resolved >/dev/null

swift package update
swift build

systemctl stop persona.socket
systemctl stop udpproxy.socket
systemctl stop tcpproxy.socket

killall tcpproxy.py >/dev/null 2>/dev/null
killall -9 tcpproxy.py >/dev/null 2>/dev/null

killall udpproxy.py >/dev/null 2>/dev/null
killall -9 udpproxy.py >/dev/null 2>/dev/null

killall Persona >/dev/null 2>/dev/null
killall 9 Persona >/dev/null 2>/dev/null

systemctl start tcpproxy.socket
systemctl start udpproxy.socket
systemctl start persona.socket

pushd frontend
go install
popd
