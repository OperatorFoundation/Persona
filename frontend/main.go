package main

import (
	"context"
	"flag"
	"fmt"
	"github.com/kataras/golog"
	"io"
	"net"
	"os"
	"os/exec"
)

func main() {
	fmt.Println("frontend is go!")

	home, homeError := os.UserHomeDir()
	if homeError != nil {
		print("could not find home directory")
		os.Exit(100)
	}

	logpath := flag.String("logpath", home+"/Persona/frontend.log", "path for log file")
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
		golog.SetLevel("error")
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

	context, cancel := context.WithCancel(context.Background())
	persona := exec.CommandContext(context, home+"/Persona/Persona")
	personaInput, inputError := persona.StdinPipe()
	if inputError != nil {
		golog.Errorf("error getting Persona stdin: %v", inputError.Error())
		os.Exit(12)
	}
	personaOutput, outputError := persona.StdoutPipe()
	if outputError != nil {
		golog.Errorf("error getting Persona stdout: %v", outputError.Error())
		os.Exit(13)
	}

	persona.Start()

	golog.Debug("launched persona")

	clientReadChannel := make(chan []byte)
	clientWriteChannel := make(chan []byte)

	personaReadChannel := make(chan []byte)
	personaWriteChannel := make(chan []byte)

	clientToChannel := ReaderToChannel{"client", clientReader, "router", clientReadChannel, func(closeError error) {
		closeWithError(closeError, 2, cancel, client)
	}}
	channelToClient := ChannelToWriter{"router", clientWriteChannel, "client", clientWriter, func(closeError error) {
		closeWithError(closeError, 3, cancel, client)
	}}

	personaToChannel := ReaderToChannel{"persona", personaOutput, "router", personaReadChannel, func(closeError error) {
		closeWithError(closeError, 4, cancel, client)
	}}
	channelToPersona := ChannelToWriter{"router", personaWriteChannel, "persona", personaInput, func(closeError error) {
		closeWithError(closeError, 5, cancel, client)
	}}

	// Non-blocking
	go clientToChannel.Pump()
	go channelToClient.Pump()

	go personaToChannel.Pump()
	go channelToPersona.Pump()

	router, routerError := NewRouter(clientReadChannel, clientWriteChannel, personaReadChannel, personaWriteChannel)
	if routerError != nil {
		closeWithError(routerError, 6, cancel, client)
	}
	router.Route() // blocking

	golog.Debug("exiting frontend abnormally, something isn't blocking")
}

func closeWithError(closeError error, exitCode int, cancel context.CancelFunc, client io.Closer) {
	golog.Debug(closeError.Error() + "")
	cancel()
	_ = client.Close()
	os.Exit(exitCode)
}
