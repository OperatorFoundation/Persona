package main

import (
	"github.com/kataras/golog"
	"net"
	"os"
)

func main() {
	// If the file doesn't exist, create it or append to the file
	logFile, openError := os.OpenFile("/root/Persona/frontend.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0666)
	if openError != nil {
		golog.Debug("Failure to open frontend log file")
	} else {
		defer logFile.Close()
		golog.AddOutput(logFile)
		golog.SetLevel("error")
	}

	client := os.NewFile(3, "systemd")

	persona, dialError := net.Dial("tcp", "127.0.0.1:1230")
	if dialError != nil {
		golog.Debug(dialError.Error())
		_ = client.Close()
		os.Exit(1)
	}

	golog.Debug("dialed persona")

	clientReadChannel := make(chan []byte)
	clientWriteChannel := make(chan []byte)

	personaReadChannel := make(chan []byte)
	personaWriteChannel := make(chan []byte)

	clientToChannel := ReaderToChannel{"client", client, "router", clientReadChannel, func(closeError error) {
		closeWithError(closeError, 2, persona, client)
	}}
	channelToClient := ChannelToWriter{"router", clientWriteChannel, "client", client, func(closeError error) {
		closeWithError(closeError, 3, persona, client)
	}}

	personaToChannel := ReaderToChannel{"persona", persona, "router", personaReadChannel, func(closeError error) {
		closeWithError(closeError, 4, persona, client)
	}}
	channelToPersona := ChannelToWriter{"router", personaWriteChannel, "persona", persona, func(closeError error) {
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

	golog.Debug("exiting frontend abnormally, something isn't blocking")
}

func closeWithError(closeError error, exitCode int, socket net.Conn, file *os.File) {
	golog.Debug(closeError.Error() + "")
	_ = socket.Close()
	_ = file.Close()
	os.Exit(exitCode)
}
