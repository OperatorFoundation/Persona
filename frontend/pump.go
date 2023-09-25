package main

import (
	"encoding/binary"
	"errors"
	"io"
	"log"
)

type ReaderToChannel struct {
	InputName string
	Input     io.Reader

	OutputName string
	Output     chan []byte

	Close func(error)
}

func (p ReaderToChannel) Pump() {
	for {
		log.Println("ReadToChannel.Pump() - reading from reader")
		lengthBytes := make([]byte, 4)
		lengthRead, lengthReadError := p.Input.Read(lengthBytes)
		if lengthReadError != nil {
			p.Close(lengthReadError)
		}
		if lengthRead != 4 {
			p.Close(errors.New("short read of length"))
		}

		length := int(binary.BigEndian.Uint32(lengthBytes))
		data := make([]byte, length)
		dataReadLength, dataReadError := p.Input.Read(data)
		if dataReadError != nil {
			p.Close(dataReadError)
		}
		if dataReadLength != length {
			p.Close(errors.New("short read of data"))
		}

		log.Printf("ReadToChannel.Pump - writing to channel %v -%d-> %v\n", p.InputName, len(data), p.OutputName)
		p.Output <- data
		log.Printf("ReadToChannel.Pump - wrote to channel %d -> %v\n", len(data), p.Output)
	}
}

type ChannelToWriter struct {
	InputName string
	Input     chan []byte

	OutputName string
	Output     io.Writer

	Close func(error)
}

func (p ChannelToWriter) Pump() {
	for {
		log.Println("ChannelToWriter.Pump() - reading data to from channel")
		data := <-p.Input

		length := len(data)
		lengthBytes := make([]byte, 4)
		binary.BigEndian.PutUint32(lengthBytes, uint32(length))

		lengthWritten, lengthWriteError := p.Output.Write(lengthBytes)
		if lengthWriteError != nil {
			p.Close(lengthWriteError)
		}
		if lengthWritten != 4 {
			p.Close(errors.New("short write on length"))
		}

		log.Printf("ChannelToWriter.Pump() - writing data to writer: %v -%d-> %v\n", p.InputName, len(data), p.OutputName)
		dataWritten, dataWriteError := p.Output.Write(data)
		if dataWriteError != nil {
			p.Close(dataWriteError)
		}
		if dataWritten != length {
			p.Close(errors.New("short write on data"))
		}
	}
}
