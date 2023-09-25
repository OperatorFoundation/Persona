package tcpproxy

import (
	"errors"
	"frontend/ip"
	"log"
	"net"
	"time"
)

type Proxy struct {
	Connections   map[string]net.Conn
	PersonaInput  chan Request
	PersonaOutput chan Response
}

func New() *Proxy {
	connections := make(map[string]net.Conn)
	input := make(chan Request)
	output := make(chan Response)

	return &Proxy{connections, input, output}
}

func (p *Proxy) Run() {
	log.Println("tcpproxy.Proxy.Run()")
	for {
		log.Println("tcpproxy.Proxy.Run - main loop")
		select {
		case request := <-p.PersonaInput:
			log.Println("tcpproxy.Proxy.Run - PersonaInput")
			switch request.Type {
			case RequestOpen:
				_, ok := p.Connections[request.Identity.String()]
				if ok {
					p.PersonaOutput <- NewErrorResponse(request.Identity, errors.New("error, Persona is asking us to open a connection that we already have open"))
					continue
				} else {
					conn, dialError := net.Dial("tcp", request.Identity.Destination)
					if dialError != nil {
						p.PersonaOutput <- NewErrorResponse(request.Identity, dialError)
						p.PersonaOutput <- NewConnectFailureResponse(request.Identity)
						continue
					}

					p.PersonaOutput <- NewConnectSuccessResponse(request.Identity)

					p.Connections[request.Identity.String()] = conn

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

			case RequestClose:
				connection, ok := p.Connections[request.Identity.String()]
				if ok {
					_ = connection.Close()
					delete(p.Connections, request.Identity.String())
					p.PersonaOutput <- NewCloseResponse(request.Identity)
				} else {
					p.PersonaOutput <- NewErrorResponse(request.Identity, errors.New("error, Persona is asking us to close a connection that we do not have"))
				}
			default:
				p.PersonaOutput <- NewErrorResponse(request.Identity, errors.New("unknown TCP proxy request type"))
				continue
			}
		}
	}
}

func (p *Proxy) ReadFromServer(server net.Conn, identity *ip.Identity, output chan Response) {
	for {
		setError := server.SetReadDeadline(time.Now().Add(100 * time.Millisecond)) // 100 milliseconds
		if setError != nil {
			output <- NewErrorResponse(identity, setError)
			delete(p.Connections, identity.String())
			return
		}

		readLength := 1024
		buffer := make([]byte, readLength)
		bytesRead, readError := server.Read(buffer)
		if bytesRead > 0 {
			if bytesRead < readLength {
				buffer = buffer[:readLength]
			}

			output <- NewDataResponse(identity, buffer)
		}
		if readError != nil {
			output <- NewErrorResponse(identity, readError)
			delete(p.Connections, identity.String())
			return
		}
	}
}
