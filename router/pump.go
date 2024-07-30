package main

import (
	"encoding/binary"
	"errors"
	"github.com/google/gopacket"
	"github.com/google/gopacket/pcapgo"
	"github.com/kataras/golog"
	"io"
	"time"
)

type ReaderToChannel struct {
	InputName string
	Input     io.Reader

	OutputName string
	Output     chan []byte

	PcapWriter *pcapgo.Writer

	Close func(string, error)
}

func (p ReaderToChannel) Pump() {
	for {
		lengthBytes := make([]byte, 4)
		lengthRead, lengthReadError := p.Input.Read(lengthBytes)
		if lengthReadError != nil {
			p.Close(p.InputName, lengthReadError)
			return
		}

		totalLengthRead := lengthRead
		for totalLengthRead < 4 {
			buffer := make([]byte, 4-totalLengthRead)
			lengthRead, lengthReadError = p.Input.Read(buffer)
			if lengthReadError != nil {
				p.Close(p.InputName, lengthReadError)
				return
			}
			copy(lengthBytes[totalLengthRead:totalLengthRead+lengthRead], buffer[:lengthRead])
			totalLengthRead = totalLengthRead + lengthRead
		}

		length := int(binary.BigEndian.Uint32(lengthBytes))
		data := make([]byte, length)

		totalLength := 0
		for totalLength < length {
			buffer := make([]byte, length-totalLength)
			dataReadLength, dataReadError := p.Input.Read(buffer)
			if dataReadLength > 0 {
				copy(data[totalLength:totalLength+dataReadLength], buffer[:dataReadLength])
				totalLength = totalLength + dataReadLength
			}
			if dataReadError != nil {
				golog.Errorf("error reading from %v: %v", p.InputName, dataReadError.Error())
				p.Close(p.InputName, dataReadError)
				return
			}
		}

		p.Output <- data

		if p.PcapWriter != nil {
			info := gopacket.CaptureInfo{time.Now(), len(data), len(data), 0, nil}
			p.PcapWriter.WritePacket(info, data)
		}
	}
}

type ChannelToWriter struct {
	InputName string
	Input     chan []byte

	OutputName string
	Output     io.Writer

	PcapWriter *pcapgo.Writer

	Close func(string, error)
}

func (p ChannelToWriter) Pump() {
	for {
		data := <-p.Input

		length := len(data)
		lengthBytes := make([]byte, 4)
		binary.BigEndian.PutUint32(lengthBytes, uint32(length))

		lengthWritten, lengthWriteError := p.Output.Write(lengthBytes)
		if lengthWriteError != nil {
			p.Close(p.OutputName, lengthWriteError)
		}
		if lengthWritten != 4 {
			p.Close(p.OutputName, errors.New("short write on length"))
		}

		dataWritten, dataWriteError := p.Output.Write(data)
		if dataWriteError != nil {
			p.Close(p.OutputName, dataWriteError)
		}
		if dataWritten != length {
			p.Close(p.OutputName, errors.New("short write on data"))
		}

		if p.PcapWriter != nil {
			info := gopacket.CaptureInfo{time.Now(), len(data), len(data), 0, nil}
			p.PcapWriter.WritePacket(info, data)
		}
	}
}
