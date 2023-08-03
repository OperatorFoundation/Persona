git pull origin main
swift package update
swift build

systemctl restart persona.socket
systemctl restart udpproxy.socket
systemctl restart tcpproxy.socket

