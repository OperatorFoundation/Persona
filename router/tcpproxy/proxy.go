package tcpproxy

import (
	"errors"
	"github.com/kataras/golog"
	"net"
	"router/ip"
	"time"
)

type Proxy struct {
	Connections   map[string]net.Conn
	PersonaInput  chan *Request
	PersonaOutput chan *Response
}

func New() *Proxy {
	connections := make(map[string]net.Conn)
	input := make(chan *Request)
	output := make(chan *Response)

	return &Proxy{connections, input, output}
}

func (p *Proxy) Run() {
	golog.Debug("tcpproxy.Proxy.Run()")
	for {
		golog.Debug("tcpproxy.Proxy.Run - main loop, waiting for message on channel input")
		request := <-p.PersonaInput
		golog.Debug("tcpproxy.Proxy.Run - PersonaInput")
		switch request.Type {
		case RequestOpen:
			golog.Debug("tcpproxy.Proxy.Run - RequestOpen")
			_, ok := p.Connections[request.Identity.String()]
			if ok {
				p.PersonaOutput <- NewErrorResponse(request.Identity, errors.New("error, Persona is asking us to open a connection that we already have open"))
				continue
			} else {
				golog.Debugf("tcpproxy.Proxy.Run - connecting to upstream server %s\n", request.Identity.Destination)
				go p.Connect(request.Identity)
			}

		case RequestWrite:
			golog.Debug("tcpproxy.Proxy.Run - RequestWrite")
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
			golog.Debug("tcpproxy.Proxy.Run - RequestClose")
			connection, ok := p.Connections[request.Identity.String()]
			if ok {
				_ = connection.Close()
				delete(p.Connections, request.Identity.String())
			} else {
				golog.Debugf("error, Persona is requesting us to close a connection that we do not have: %s (%d open connections)", request.Identity.String(), len(p.Connections))

				golog.Debug("tcpproxy.Proxy.Run - RequestClose - writing ResponseError")
				p.PersonaOutput <- NewErrorResponse(request.Identity, errors.New("error, Persona is asking us to close a connection that we do not have"))
				golog.Debug("tcpproxy.Proxy.Run - RequestClose - wrote ResponseError")
			}
		default:
			golog.Debug("tcpproxy.Proxy.Run - RequestClose - writing ResponseError due to unknown type")
			p.PersonaOutput <- NewErrorResponse(request.Identity, errors.New("unknown TCP proxy request type"))
			golog.Debug("tcpproxy.Proxy.Run - RequestClose - wrote ResponseError due to unknown type")
			continue
		}
	}
}

func (p *Proxy) Connect(identity *ip.Identity) {
	golog.Debugf("dialing %s\n", identity.Destination)
	conn, dialError := net.Dial("tcp", identity.Destination)
	if dialError != nil {
		golog.Debugf("error dialing %s - %v\n", identity.Destination, dialError)
		p.PersonaOutput <- NewErrorResponse(identity, dialError)
		p.PersonaOutput <- NewConnectFailureResponse(identity)
		return
	}

	p.Connections[identity.String()] = conn

	go p.ReadFromServer(conn, identity, p.PersonaOutput)

	golog.Debugf(" dialing %s\n", identity.Destination)
	golog.Debug("sending connect  response")
	p.PersonaOutput <- NewConnectSuccessResponse(identity)
}

func (p *Proxy) ReadFromServer(server net.Conn, identity *ip.Identity, output chan *Response) {
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
				buffer = buffer[:bytesRead]
			}

			output <- NewDataResponse(identity, buffer)
		}
		if readError != nil {
			// Ignore timeouts, timeouts are fine, they are what allow us to do short reads.
			timeoutError, ok := readError.(*net.OpError)
			if ok {
				if timeoutError.Timeout() {
					continue
				}
			}

			delete(p.Connections, identity.String())
			return
		}
	}
}
