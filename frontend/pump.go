package main

import (
	"encoding/binary"
	"errors"
	"io"
)

type Pumpable interface {
	io.Reader
	io.Writer
}

type PumpStation struct {
	Left  Pumpable
	Right Pumpable
	Close func(error)
}

// Run - blocking
func (ps PumpStation) Run() {
	print("PumpStation.Run()\n")
	leftToRight := Pump{ps.Left, ps.Right, ps.Close}
	rightToLeft := Pump{ps.Right, ps.Left, ps.Close}

	print("PumpStation.Run() - leftToRight\n")
	go leftToRight.Pump() // non-blocking
	print("PumpStation.Run() - rightToLeft\n")
	rightToLeft.Pump() // blocking
	print("PumpStation.Run() - done\n")
}

type Pump struct {
	Input  io.Reader
	Output io.Writer
	Close  func(error)
}

func (p Pump) Pump() {
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
}
