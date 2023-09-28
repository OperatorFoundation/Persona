package main

import (
	"errors"
	"frontend/tcpproxy"
	"frontend/udpproxy"
	"github.com/kataras/golog"
	"time"
)

type Router struct {
	Tcp *tcpproxy.Proxy
	Udp *udpproxy.Proxy

	ClientReadChannel  chan []byte
	ClientWriteChannel chan []byte

	PersonaReadChannel  chan []byte
	PersonaWriteChannel chan []byte
}

func NewRouter(clientRead chan []byte, clientWrite chan []byte, personaRead chan []byte, personaWrite chan []byte) (*Router, error) {
	tcp := tcpproxy.New()
	if tcp == nil {
		return nil, errors.New("could not initialize TCP proxy")
	}

	golog.Debug("about to run tcpproxy")
	go tcp.Run()
	golog.Debug("tcpproxy was run")

	udp := udpproxy.New()
	if udp == nil {
		return nil, errors.New("could not initialize UDP proxy")
	}

	golog.Debug("about to run udpproxy")
	go udp.Run()
	golog.Debug("udpproxy was run")

	return &Router{tcp, udp, clientRead, clientWrite, personaRead, personaWrite}, nil
}

func (r *Router) Route() {
	golog.Debug("Router.Route()")
	go r.RoutePersona()
	go r.RouteTcpproxy()
	go r.RouteUdpproxy()

	golog.Debug("Router.Route - all router goroutines started, starting client router main loop")
	r.RouteClient()
}

func (r *Router) RouteClient() {
	for {
		// Received data from the client
		clientData := <-r.ClientReadChannel
		golog.Debug("Router.Route - ClientReadChannel")
		// Forward data to Persona
		message := make([]byte, 0)
		message = append(message, byte(Client))
		message = append(message, clientData...)

		r.PersonaWriteChannel <- message
	}
}

func (r *Router) RoutePersona() {
	for {
		personaData := <-r.PersonaReadChannel
		golog.Debug("Router.Route - PersonaReadChannel")
		if len(personaData) < 1 {
			golog.Debug("error, personaData was empty")
			continue
		}

		subsystem := Subsystem(personaData[0])
		data := personaData[1:]

		switch subsystem {
		case Client:
			// FIXME - remove this temporary hack
			time.Sleep(100 * time.Millisecond) // 100 ms
			r.ClientWriteChannel <- data
		case Udpproxy:
			request := udpproxy.NewRequest(data)
			if request == nil {
				golog.Debug("error, bad udpproxy request")
				continue
			} else {
				r.Udp.PersonaInput <- request
			}
		case Tcpproxy:
			request := tcpproxy.NewRequest(data)
			if request == nil {
				golog.Debug("error, bad tcpproxy request")
				continue
			} else {
				golog.Debug("sending Persona request to tcpproxy")
				r.Tcp.PersonaInput <- request
				golog.Debug("sent Persona request to tcpproxy")
			}
		default:
			golog.Debug("bad message type")
		}
	}
}

func (r *Router) RouteTcpproxy() {
	for {
		golog.Debug("Router.RouteTcpproxy - waiting for message")
		tcpProxyResponse := <-r.Tcp.PersonaOutput
		golog.Debug("Router.RouteTcpproxy - read message")
		switch tcpProxyResponse.Type {
		case tcpproxy.ResponseData:
			messageData, dataError := tcpProxyResponse.Data()
			if dataError != nil {
				golog.Debug(dataError.Error())
				continue
			}

			message := make([]byte, 0)
			message = append(message, byte(Tcpproxy))
			message = append(message, messageData...)

			r.PersonaWriteChannel <- message

		case tcpproxy.ResponseClose:
			messageData, dataError := tcpProxyResponse.Data()
			if dataError != nil {
				golog.Debug(dataError.Error())
				continue
			}

			message := make([]byte, 0)
			message = append(message, byte(Tcpproxy))
			message = append(message, messageData...)

			r.PersonaWriteChannel <- message

		case tcpproxy.ResponseError:
			if tcpProxyResponse.Error != nil {
				golog.Debug(tcpProxyResponse.Error.Error())

				messageData, dataError := tcpProxyResponse.Data()
				if dataError != nil {
					golog.Debug(dataError.Error())
					continue
				}

				message := make([]byte, 0)
				message = append(message, byte(Tcpproxy))
				message = append(message, messageData...)

				r.PersonaWriteChannel <- message
			}

		case tcpproxy.ResponseConnectSuccess:
			messageData, dataError := tcpProxyResponse.Data()
			if dataError != nil {
				golog.Debug(dataError.Error())
				continue
			}

			message := make([]byte, 0)
			message = append(message, byte(Tcpproxy))
			message = append(message, messageData...)

			r.PersonaWriteChannel <- message

		case tcpproxy.ResponseConnectFailure:
			messageData, dataError := tcpProxyResponse.Data()
			if dataError != nil {
				golog.Debug(dataError.Error())
				continue
			}

			message := make([]byte, 0)
			message = append(message, byte(Tcpproxy))
			message = append(message, messageData...)

			r.PersonaWriteChannel <- message
		}
	}
}

func (r *Router) RouteUdpproxy() {
	for {
		udpProxyResponse := <-r.Udp.PersonaOutput
		golog.Debug("Router.Route - UdpProxyReadChannel")
		switch udpProxyResponse.Type {
		case udpproxy.ResponseData:
			messageData, dataError := udpProxyResponse.Data()
			if dataError != nil {
				golog.Debug(dataError.Error())
				continue
			}

			message := make([]byte, 0)
			message = append(message, byte(Udpproxy))
			message = append(message, messageData...)

			r.PersonaWriteChannel <- message

		case udpproxy.ResponseError:
			messageData, dataError := udpProxyResponse.Data()
			if dataError != nil {
				golog.Debug(dataError.Error())
				continue
			}

			if udpProxyResponse.Error != nil {
				golog.Debug(udpProxyResponse.Error.Error())

				message := make([]byte, 0)
				message = append(message, byte(Udpproxy))
				message = append(message, messageData...)

				r.PersonaWriteChannel <- message
			}
		}
	}
}
