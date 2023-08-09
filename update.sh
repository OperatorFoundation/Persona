git pull origin main
swift package update
swift build

systemctl stop persona.socket
systemctl stop udpproxy.socket
systemctl stop tcpproxy.socket

killall main.py
killall -9 main.py

killall Persona
killall 9 Persona

systemctl start tcpproxy.socket
systemctl start udpproxy.socket
systemctl start persona.socket
