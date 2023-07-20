cp systemd/* /etc/systemd/system
systemctl daemon-reload
systemctl start persona.socket
systemctl status persona.socket
