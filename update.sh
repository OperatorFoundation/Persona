git pull origin main

swift package reset
rm -rf .build >/dev/null
rm -rf .swiftpm >/dev/null
rm -rf Package.resolved >/dev/null

swift package update
swift build -c release
cp .build/x86_64-unknown-linux-gnu/release/Persona .
cp .build/arm64-apple-macosx/release/Persona .

pushd frontend
go get frontend
go install
popd

systemctl stop frontend.socket
systemctl stop frontend

killall Persona >/dev/null 2>/dev/null
killall -9 Persona >/dev/null 2>/dev/null

killall frontend >/dev/null 2>/dev/null
killall -9 frontend >/dev/null 2>/dev/null

systemctl start frontend
