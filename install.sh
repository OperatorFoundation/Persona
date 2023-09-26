git pull origin main
swift build

apt install golang
pushd frontend
go get frontend
go install
popd

rm /etc/systemd/system/tcpproxy* >/dev/null 2>/dev/null
rm /etc/systemd/system/udpproxy* >/dev/null 2>/dev/null

cp etc/systemd/* /etc/systemd/system
systemctl daemon-reload
systemctl start persona.socket
systemctl status persona.socket
systemctl start frontend.socket
systemctl status frontend.socket

apt install xinetd
cp etc/xinetd/* /etc/xinetd.d
systemctl restart xinetd

ufw allow 22   # ssh
ufw allow 1234 # frontend
ufw allow 1230 # Persona
ufw deny 7     # echo
ufw enable
