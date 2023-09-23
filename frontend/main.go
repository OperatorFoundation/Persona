package main

import (
	"net"
	"os"
)

func main() {
	client := os.NewFile(3, "systemd")

	persona, dialError := net.Dial("tcp", "127.0.0.1:1230")
	if dialError != nil {
		print(dialError.Error())
		_ = client.Close()
		os.Exit(1)
	}

	clientToPersona := Pump{client, persona, func(closeError error) {
		closeWithError(closeError, 2, persona, client)
	}}
	personaToClient := Pump{persona, client, func(closeError error) {
		closeWithError(closeError, 3, persona, client)
	}}

	go clientToPersona.Pump()

	personaToClient.Pump()
}

func closeWithError(closeError error, exitCode int, socket net.Conn, file *os.File) {
	print(closeError.Error())
	_ = socket.Close()
	_ = file.Close()
	os.Exit(exitCode)
}
