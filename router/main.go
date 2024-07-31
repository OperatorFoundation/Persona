package main

import (
	"context"
	"flag"
	"fmt"
	"github.com/google/gopacket/layers"
	"github.com/google/gopacket/pcapgo"
	"github.com/kataras/golog"
	"io"
	"net"
	"os"
	"os/exec"
)

func main() {
	fmt.Println("router is go!")

	home, homeError := os.UserHomeDir()
	if homeError != nil {
		print("could not find home directory")
		home = "/root"
	}

	logpath := flag.String("logpath", home+"/Persona/router.log", "path for log file")
	socket := flag.Bool("socket", false, "enable single-connection socket mode for testing, by default uses systemd mode instead")
	writePcap := flag.Bool("writePcap", false, "write packets to .pcap file")
	flag.Parse()

	// If the file doesn't exist, create it or append to the file
	logFile, openError := os.OpenFile(*logpath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0666)
	if openError != nil {
		fmt.Printf("Failure to open router log file %v\n", *logpath)
	} else {
		defer func() {
			_ = logFile.Close()
		}()

		golog.AddOutput(logFile)
		golog.SetLevel("error")
	}

	var pcapWriter *pcapgo.Writer
	if *writePcap {
		pcapFile, openError := os.OpenFile(home+"/Persona/persona.pcap", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0666)
		if openError != nil {
			golog.Errorf("error opening pcap file %v", openError.Error())
			pcapWriter = nil
		} else {
			pcapWriter = pcapgo.NewWriter(pcapFile)
			pcapWriter.WriteFileHeader(65536, layers.LinkTypeIPv4) // new file, must do this.
			defer func() {
				pcapFile.Close()
			}()
		}
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

		for {
			connection, acceptError := listener.Accept()
			if acceptError != nil {
				golog.Errorf("error accepting: %v", acceptError.Error())
				os.Exit(11)
			}

			client = connection
			clientReader = connection
			clientWriter = connection

			go handleConnection(home, client, clientReader, clientWriter, pcapWriter)
		}
	} else {
		systemd := os.NewFile(3, "systemd")
		client = systemd
		clientReader = systemd
		clientWriter = systemd

		handleConnection(home, client, clientReader, clientWriter, pcapWriter)
	}
}

func handleConnection(home string, client io.Closer, clientReader io.Reader, clientWriter io.Writer, pcapWriter *pcapgo.Writer) {
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

	clientToChannel := ReaderToChannel{"client", clientReader, "router", clientReadChannel, pcapWriter, func(closer string, closeError error) {
		closeWithError(closer, closeError, 0, cancel, client)
	}}
	channelToClient := ChannelToWriter{"router", clientWriteChannel, "client", clientWriter, pcapWriter, func(closer string, closeError error) {
		closeWithError(closer, closeError, 0, cancel, client)
	}}

	personaToChannel := ReaderToChannel{"persona", personaOutput, "router", personaReadChannel, nil, func(closer string, closeError error) {
		closeWithError(closer, closeError, 4, cancel, client)
	}}
	channelToPersona := ChannelToWriter{"router", personaWriteChannel, "persona", personaInput, nil, func(closer string, closeError error) {
		closeWithError(closer, closeError, 5, cancel, client)
	}}

	// Non-blocking
	go clientToChannel.Pump()
	go channelToClient.Pump()

	go personaToChannel.Pump()
	go channelToPersona.Pump()

	router, routerError := NewRouter(clientReadChannel, clientWriteChannel, personaReadChannel, personaWriteChannel)
	if routerError != nil {
		closeWithError("router", routerError, 6, cancel, client)
	}
	router.Route() // blocking

	golog.Debug("exiting router abnormally, something isn't blocking")
}

func closeWithError(closer string, closeError error, exitCode int, cancel context.CancelFunc, client io.Closer) {
	golog.Debugf("Closing %s with an error: %v", closer, closeError.Error())
	cancel()
	_ = client.Close()
	os.Exit(exitCode)
}
