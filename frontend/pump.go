package main

import (
	"encoding/binary"
	"errors"
	"io"
)

type ReaderToChannel struct {
	Input  io.Reader
	Output chan []byte
	Close  func(error)
}

func (p ReaderToChannel) Pump() {
	for {
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

		p.Output <- data
	}
}

type ChannelToWriter struct {
	Input  chan []byte
	Output io.Writer
	Close  func(error)
}

func (p ChannelToWriter) Pump() {
	for {
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

		print("Pump.Pump() - writing data %d", len(data))
		dataWritten, dataWriteError := p.Output.Write(data)
		if dataWriteError != nil {
			p.Close(dataWriteError)
		}
		if dataWritten != length {
			p.Close(errors.New("short write on data"))
		}
	}
}
