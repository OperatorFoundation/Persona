package main

import (
	"log"
	"net"
	"os"
)

func main() {
	// If the file doesn't exist, create it or append to the file
	logFile, openError := os.OpenFile("/root/Persona/frontend.txt", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0666)
	if openError != nil {
		log.Println("Failure to open frontend log file")
	} else {
		log.SetOutput(logFile)
	}

	client := os.NewFile(3, "systemd")

	persona, dialError := net.Dial("tcp", "127.0.0.1:1230")
	if dialError != nil {
		log.Println(dialError.Error())
		_ = client.Close()
		os.Exit(1)
	}

	log.Println("dialed persona %v", persona)

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
	log.Println(closeError.Error() + "\n")
	_ = socket.Close()
	_ = file.Close()
	os.Exit(exitCode)
}
