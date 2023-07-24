git pull origin main
swift build

systemctl restart persona.socket
systemctl restart udpproxy.socket

