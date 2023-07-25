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

apt install xinetd
cp etc/xinetd/* /etc/xinetd.d
systemctl restart xinetd

ufw allow 22
ufw allow 1234
ufw deny 7
ufw deny 1233
ufw enable
