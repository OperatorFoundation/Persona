cp etc/systemd/* /etc/systemd/system
systemctl daemon-reload
systemctl start persona.socket
systemctl status persona.socket

apt install xinetd
cp etc/xinetd/* /etc/xinetd.d
systemctl restart xinetd
