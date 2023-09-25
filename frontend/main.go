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

	print("dialed persona %v", persona)

	clientReadChannel := make(chan []byte)
	clientWriteChannel := make(chan []byte)

	personaReadChannel := make(chan []byte)
	personaWriteChannel := make(chan []byte)

	clientToChannel := ReaderToChannel{client, clientReadChannel, func(closeError error) {
		closeWithError(closeError, 2, persona, client)
	}}
	channelToClient := ChannelToWriter{clientWriteChannel, client, func(closeError error) {
		closeWithError(closeError, 3, persona, client)
	}}

	personaToChannel := ReaderToChannel{persona, personaReadChannel, func(closeError error) {
		closeWithError(closeError, 4, persona, client)
	}}
	channelToPersona := ChannelToWriter{personaWriteChannel, persona, func(closeError error) {
		closeWithError(closeError, 5, persona, client)
	}}

	// Non-blocking
	go clientToChannel.Pump()
	go channelToClient.Pump()

	go personaToChannel.Pump()
	go channelToPersona.Pump()

	router, routerError := NewRouter(clientReadChannel, clientWriteChannel, personaReadChannel, personaWriteChannel)
	if routerError != nil {
		closeWithError(routerError, 6, persona, client)
	}
	router.Route() // blocking
}

func closeWithError(closeError error, exitCode int, socket net.Conn, file *os.File) {
	print(closeError.Error() + "\n")
	_ = socket.Close()
	_ = file.Close()
	os.Exit(exitCode)
}
