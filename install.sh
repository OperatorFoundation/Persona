git pull origin main
swift build -c release
cp .build/x86_64-unknown-linux-gnu/release/Persona .
cp .build/arm64-apple-macosx/release/Persona .

apt install golang
pushd frontend
go get frontend
go install
popd

rm /etc/systemd/system/frontend*
rm /etc/systemd/system/persona*

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
