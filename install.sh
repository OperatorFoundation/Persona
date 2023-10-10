git stash
git pull origin main
swift build -c release
cp .build/x86_64-unknown-linux-gnu/release/Persona . >/dev/null 2>/dev/null
cp .build/arm64-apple-macosx/release/Persona . >/dev/null 2>/dev/null

apt install golang
pushd frontend
go get frontend
go install
popd
pushd router
go get router
go install
popd

rm /etc/systemd/system/persona*
rm /etc/systemd/system/frontend*
rm /etc/systemd/system/tcpproxy*
rm /etc/systemd/system/udpproxy*
rm /etc/systemd/system/router*

cp etc/systemd/* /etc/systemd/system
systemctl daemon-reload
systemctl start frontend

apt install xinetd
cp etc/xinetd/* /etc/xinetd.d
systemctl restart xinetd

ufw allow 22   # ssh
ufw allow 1234 # frontend
ufw deny 7     # echo
ufw --force enable
