package main

import (
	"context"
	"flag"
	"fmt"
	"github.com/kataras/golog"
	"net"
	"os"
	"os/exec"
)

func main() {
	fmt.Println("frontend is go!")

	handlers := make([]context.CancelFunc, 0)
	defer func() {
		for _, handler := range handlers {
			handler()
		}
	}()

	home, homeError := os.UserHomeDir()
	if homeError != nil {
		print("could not find home directory")
		home = "/root"
	}

	logpath := flag.String("logpath", home+"/Persona/frontend.log", "path for log file")
	writePcap := flag.Bool("writePcap", false, "record packets to a pcap file")
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

		go handleConnection(home, connection, *writePcap, &handlers)
	}
}

func handleConnection(home string, connection net.Conn, writePcap bool, handlers *[]context.CancelFunc) {
	golog.Debug("launching router subprocess")
	ctx, cancel := context.WithCancel(context.Background())
	*handlers = append(*handlers, cancel)

	var command string
	if writePcap {
		command = fmt.Sprintf("%s/go/bin/router -writePcap", home)
	} else {
		command = fmt.Sprintf("%s/go/bin/router", home)
	}

	router := exec.CommandContext(ctx, command)
	file, castError := connection.(*net.TCPConn).File()
	if castError != nil {
		golog.Errorf("error casting to TCPConn %v", castError.Error())
		return
	}
	router.ExtraFiles = []*os.File{file}
	startError := router.Start()
	if startError != nil {
		golog.Errorf("error starting process %v", startError.Error())
		return
	}

	golog.Debug("launched router")

	go func() {
		router.Wait()
	}()
}
