package main

import (
	"flag"
	"fmt"
	"github.com/kataras/golog"
	"io"
	"net"
	"os"
)

func main() {
	fmt.Println("frontend is go!")

	logpath := flag.String("logpath", "/root/Persona/frontend.log", "path for log file")
	socket := flag.Bool("socket", false, "enable single-connection socket mode for testing, by default uses systemd mode instead")
	flag.Parse()

	// If the file doesn't exist, create it or append to the file
	logFile, openError := os.OpenFile(*logpath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0666)
	if openError != nil {
		fmt.Printf("Failure to open frontend log file %v\n", *logpath)
	} else {
		defer func() {
			_ = logFile.Close()
		}()

		golog.AddOutput(logFile)
		golog.SetLevel("debug")
	}

	var client io.Closer
	var clientReader io.Reader
	var clientWriter io.Writer

	if *socket {
		listener, listenError := net.Listen("tcp", "0.0.0.0:1234")
		if listenError != nil {
			golog.Errorf("error listening: %v", listenError.Error())
			os.Exit(10)
		}

		connection, acceptError := listener.Accept()
		if acceptError != nil {
			golog.Errorf("error accepting: %v", acceptError.Error())
			os.Exit(11)
		}

		client = connection
		clientReader = connection
		clientWriter = connection
	} else {
		systemd := os.NewFile(3, "systemd")
		client = systemd
		clientReader = systemd
		clientWriter = systemd
	}

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

	clientToChannel := ReaderToChannel{"client", clientReader, "router", clientReadChannel, func(closeError error) {
		closeWithError(closeError, 2, persona, client)
	}}
	channelToClient := ChannelToWriter{"router", clientWriteChannel, "client", clientWriter, func(closeError error) {
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

func closeWithError(closeError error, exitCode int, socket net.Conn, file io.Closer) {
	golog.Debug(closeError.Error() + "")
	_ = socket.Close()
	_ = file.Close()
	os.Exit(exitCode)
}
