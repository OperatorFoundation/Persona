package udpproxy

import (
	"encoding/binary"
	"errors"
	"frontend/ip"
	"net"
	"time"
)

type Proxy struct {
	Connections   map[string]*net.UDPConn
	LastUsed      map[string]time.Time
	PersonaInput  chan Request
	PersonaOutput chan Response
}

func New() *Proxy {
	connections := make(map[string]*net.UDPConn)
	lastUsed := make(map[string]time.Time)
	input := make(chan Request)
	output := make(chan Response)

	return &Proxy{connections, lastUsed, input, output}
}

func (p Proxy) Run() {
	go p.Cleanup()

	for {
		select {
		case request := <-p.PersonaInput:
			switch request.Type {
			case RequestOpen:
				_, ok := p.Connections[request.Identity.String()]
				if ok {
					p.PersonaOutput <- NewErrorResponse(request.Identity, errors.New("error, Persona is asking us to open a connection that we already have open"))
					continue
				} else {
					addr, resolveError := net.ResolveUDPAddr("udp", request.Identity.Destination)
					if resolveError != nil {
						p.PersonaOutput <- NewErrorResponse(request.Identity, resolveError)
						continue
					}
					conn, dialError := net.DialUDP("udp", nil, addr)
					if dialError != nil {
						p.PersonaOutput <- NewErrorResponse(request.Identity, dialError)
						continue
					}

					bytesWritten, writeError := conn.Write(request.Identity.Data)
					if writeError != nil {
						p.PersonaOutput <- NewErrorResponse(request.Identity, writeError)
						continue
					}
					if bytesWritten != len(request.Identity.Data) {
						p.PersonaOutput <- NewErrorResponse(request.Identity, errors.New("short write setting identity for udpproxy"))
						_ = conn.Close()
						continue
					}

					p.Connections[request.Identity.String()] = conn
					p.LastUsed[request.Identity.String()] = time.Now()

					go p.ReadFromServer(conn, request.Identity, p.PersonaOutput)
				}

			case RequestWrite:
				if request.Data == nil || len(request.Data) == 0 {
					p.PersonaOutput <- NewErrorResponse(request.Identity, errors.New("error, bad write request, no data to write"))
					continue
				}

				connection, ok := p.Connections[request.Identity.String()]
				if ok {
					bytesWrote, writeError := connection.Write(request.Data)
					if writeError != nil {
						p.PersonaOutput <- NewErrorResponse(request.Identity, errors.New("error, bad write"))
						continue
					}
					if bytesWrote != len(request.Data) {
						p.PersonaOutput <- NewErrorResponse(request.Identity, errors.New("error, short write"))
						continue
					}
				} else {
					p.PersonaOutput <- NewErrorResponse(request.Identity, errors.New("error, Persona is asking us to close a connection that we do not have"))
					continue
				}
			}
		}
	}
}

func (p Proxy) ReadFromServer(server net.Conn, identity *ip.Identity, output chan Response) {
	for {
		lengthBytes := make([]byte, 4)
		lengthRead, lengthReadError := server.Read(lengthBytes)
		if lengthReadError != nil {
			output <- NewErrorResponse(identity, lengthReadError)
			_ = server.Close()
			delete(p.Connections, identity.String())
			delete(p.LastUsed, identity.String())
			return
		}
		if lengthRead != 4 {
			output <- NewErrorResponse(identity, errors.New("short read of length"))
			_ = server.Close()
			delete(p.Connections, identity.String())
			delete(p.LastUsed, identity.String())
			return
		}

		length := int(binary.BigEndian.Uint32(lengthBytes))

		data := make([]byte, length)
		dataReadLength, dataReadError := server.Read(data)
		if dataReadError != nil {
			output <- NewErrorResponse(identity, dataReadError)
			_ = server.Close()
			delete(p.Connections, identity.String())
			delete(p.LastUsed, identity.String())
			return
		}
		if dataReadLength != length {
			output <- NewErrorResponse(identity, errors.New("short read of data"))
			_ = server.Close()
			delete(p.Connections, identity.String())
			delete(p.LastUsed, identity.String())
			return
		}

		output <- NewDataResponse(identity, data)
	}
}

func (p Proxy) Cleanup() {
	for {
		timer := time.NewTimer(60 * time.Second) // 60 seconds

		<-timer.C // wait on timer channel to fire

		now := time.Now()

		for identityString, lastUsed := range p.LastUsed {
			identity, identityError := ip.NewIdentityFromString(identityString)
			if identityError != nil {
				print("error, malformed identity string")
				continue
			}

			if now.Sub(lastUsed).Seconds() > 60 {
				p.PersonaOutput <- NewCloseResponse(identity)
				connection, ok := p.Connections[identityString]
				if ok {
					_ = connection.Close()
					delete(p.Connections, identityString)
					delete(p.LastUsed, identityString)
				} else {
					print("error, lastUsed out of sync with connections")
				}
			}
		}
	}
}
