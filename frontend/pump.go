package main

import (
	"encoding/binary"
	"errors"
	"io"
)

type Pump struct {
	Input  io.Reader
	Output io.Writer
	Close  func(error)
}

func (p Pump) Pump() {
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

	lengthWritten, lengthWriteError := p.Output.Write(lengthBytes)
	if lengthWriteError != nil {
		p.Close(lengthWriteError)
	}
	if lengthWritten != 4 {
		p.Close(errors.New("short write on length"))
	}

	dataWritten, dataWriteError := p.Output.Write(data)
	if dataWriteError != nil {
		p.Close(dataWriteError)
	}
	if dataWritten != 4 {
		p.Close(errors.New("short write on data"))
	}
}
