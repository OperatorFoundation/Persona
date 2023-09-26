package main

import (
	"encoding/binary"
	"errors"
	"github.com/kataras/golog"
	"io"
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
		golog.Debug("ReadToChannel.Pump() - reading from reader")
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

		golog.Debugf("ReadToChannel.Pump - writing to channel %v -%d-> %v", p.InputName, len(data), p.OutputName)
		p.Output <- data
		golog.Debugf("ReadToChannel.Pump - wrote to channel %d -> %v", len(data), p.Output)
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
		golog.Debug("ChannelToWriter.Pump() - reading data to from channel")
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

		golog.Debugf("ChannelToWriter.Pump() - writing data to writer: %v -%d-> %v", p.InputName, len(data), p.OutputName)
		dataWritten, dataWriteError := p.Output.Write(data)
		if dataWriteError != nil {
			p.Close(dataWriteError)
		}
		if dataWritten != length {
			p.Close(errors.New("short write on data"))
		}
	}
}
