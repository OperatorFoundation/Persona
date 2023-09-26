package udpproxy

import (
	"errors"
	"frontend/ip"
	"log"
	"net"
	"time"
)

type Proxy struct {
	Connections   map[string]*net.UDPConn
	LastUsed      map[string]time.Time
	PersonaInput  chan *Request
	PersonaOutput chan *Response
}

func New() *Proxy {
	connections := make(map[string]*net.UDPConn)
	lastUsed := make(map[string]time.Time)
	input := make(chan *Request)
	output := make(chan *Response)

	return &Proxy{connections, lastUsed, input, output}
}

func (p *Proxy) Run() {
	go p.Cleanup()

	log.Println("udpproxy.Proxy.Run()")
	for {
		log.Println("udpproxy.Proxy.Run - main loop")
		select {
		case request := <-p.PersonaInput:
			log.Println("udpproxy.Proxy.Run - request received")
			switch request.Type {
			case RequestWrite:
				log.Println("udpproxy.Proxy.Run - request is a write")
				if request.Data == nil || len(request.Data) == 0 {
					p.PersonaOutput <- NewErrorResponse(request.Identity, errors.New("error, bad write request, no data to write"))
					continue
				}

				connection, ok := p.Connections[request.Identity.String()]
				if !ok {
					log.Println("udpproxy.Proxy.Run - new UDP connection")
					addr, resolveError := net.ResolveUDPAddr("udp", request.Identity.Destination)
					if resolveError != nil {
						p.PersonaOutput <- NewErrorResponse(request.Identity, resolveError)
						continue
					}
					newConnection, dialError := net.DialUDP("udp", nil, addr)
					connection = newConnection

					if dialError != nil {
						p.PersonaOutput <- NewErrorResponse(request.Identity, dialError)
						continue
					}

					p.Connections[request.Identity.String()] = connection
					p.LastUsed[request.Identity.String()] = time.Now()

					go p.ReadFromServer(connection, request.Identity, p.PersonaOutput)
				}

				log.Printf("udpproxy.Proxy.Run - writing %d\n bytes upstream", len(request.Data))
				bytesWrote, writeError := connection.Write(request.Data)
				if writeError != nil {
					p.PersonaOutput <- NewErrorResponse(request.Identity, errors.New("error, bad write"))
					continue
				}
				if bytesWrote != len(request.Data) {
					p.PersonaOutput <- NewErrorResponse(request.Identity, errors.New("error, short write"))
					continue
				}
				log.Printf("udpproxy.Proxy.Run - wrote %d\n bytes upstream", bytesWrote)
			}
		}
	}
}

func (p *Proxy) ReadFromServer(server *net.UDPConn, identity *ip.Identity, output chan *Response) {
	for {
		length := 2048
		data := make([]byte, length)
		dataReadLength, sourceAddress, dataReadError := server.ReadFromUDP(data)
		if dataReadError != nil {
			output <- NewErrorResponse(identity, dataReadError)
			_ = server.Close()
			delete(p.Connections, identity.String())
			delete(p.LastUsed, identity.String())
			return
		}
		if dataReadLength != length {
			data = data[:dataReadLength]
		}

		if sourceAddress.String() != identity.Destination {
			log.Printf("source of incoming UDP packet %v does not match connection Identity %v", sourceAddress.String(), identity.Destination)
			continue
		}

		output <- NewDataResponse(identity, data)
	}
}

func (p *Proxy) Cleanup() {
	for {
		timer := time.NewTimer(60 * time.Second) // 60 seconds

		<-timer.C // wait on timer channel to fire

		now := time.Now()

		for identityString, lastUsed := range p.LastUsed {
			if now.Sub(lastUsed).Seconds() > 60 {
				log.Printf("closing old connection %v\n", identityString)
				connection, ok := p.Connections[identityString]
				if ok {
					_ = connection.Close()
					delete(p.Connections, identityString)
					delete(p.LastUsed, identityString)
				} else {
					log.Println("error, lastUsed out of sync with connections")
				}
			}
		}
	}
}
