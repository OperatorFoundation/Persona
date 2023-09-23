git pull origin main
swift build

cp etc/systemd/* /etc/systemd/system
systemctl daemon-reload
systemctl start persona.socket
systemctl status persona.socket
systemctl start udpproxy.socket
systemctl status udpproxy.socket
systemctl start tcpproxy.socket
systemctl status tcpproxy.socket
systemctl start frontend.socket
systemctl status frontend.socket

apt install xinetd
cp etc/xinetd/* /etc/xinetd.d
systemctl restart xinetd

ufw allow 22   # ssh
ufw allow 1234 # frontend
ufw allow 1230 # Persona
ufw deny 7     # echo
ufw deny 1233  # tcpproxy
ufw deny 1232  # udpproxy
ufw enable
