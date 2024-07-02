package main

import (
	"errors"
	"github.com/kataras/golog"
	"router/tcpproxy"
	"router/timer"
	"router/udpproxy"
	"time"
)

type Router struct {
	Tcp   *tcpproxy.Proxy
	Udp   *udpproxy.Proxy
	Timer *timer.Proxy

	ClientReadChannel  chan []byte
	ClientWriteChannel chan []byte

	PersonaReadChannel  chan []byte
	PersonaWriteChannel chan []byte

	LastClientWrite time.Time
}

func NewRouter(clientRead chan []byte, clientWrite chan []byte, personaRead chan []byte, personaWrite chan []byte) (*Router, error) {
	tcp := tcpproxy.New()
	if tcp == nil {
		return nil, errors.New("could not initialize TCP proxy")
	}

	go tcp.Run()

	udp := udpproxy.New()
	if udp == nil {
		return nil, errors.New("could not initialize UDP proxy")
	}

	go udp.Run()

	timerProxy := timer.New()
	if timerProxy == nil {
		return nil, errors.New("could not initialize timer proxy")
	}

	go timerProxy.Run()

	now := time.Now()

	return &Router{tcp, udp, timerProxy, clientRead, clientWrite, personaRead, personaWrite, now}, nil
}

func (r *Router) Route() {
	go r.RoutePersona()
	go r.RouteTcpproxy()
	go r.RouteUdpproxy()
	go r.RouteTimerProxy()

	r.RouteClient()
}

func (r *Router) RouteClient() {
	for {
		// Received data from the client
		clientData := <-r.ClientReadChannel
		golog.Debugf("-> Client -> Persona message is %v bytes: %x", len(clientData), clientData)
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
		} else {
			golog.Debugf("--> RoutePersona [%v bytes]: %x", len(personaData), personaData)
		}

		subsystem := Subsystem(personaData[0])
		data := personaData[1:]

		switch subsystem {
		case Client:
			golog.Debugf("---> Persona -> Client: [%v bytes]:%x", len(data), data)
			r.ClientWriteChannel <- data
		case Udpproxy:
			request := udpproxy.NewRequest(data)

			if request == nil {
				golog.Debug("~ error, bad udpproxy request")
				continue
			} else {
				golog.Debugf("---> Persona -> Udpproxy: %v", request)
				r.Udp.PersonaInput <- request
			}
		case Tcpproxy:
			request := tcpproxy.NewRequest(data)
			if request == nil {
				golog.Debug("~ error, bad Tcpproxy request")
				continue
			} else {
				golog.Debugf("---> Persona -> Tcpproxy: %v", request)
				r.Tcp.PersonaInput <- request
			}
		case Timer:
		  request := timer.NewRequest(data)
		  if request == nil {
		    golog.Debug("error, bad timer request")
		    continue
		  } else {
            golog.Debugf("---> Persona -> Timer: %v", request)
		    r.Timer.PersonaInput <- request
		  }
		default:
			golog.Debugf("~ 💥 bad message type %v", subsystem)
		}
	}
}

func (r *Router) RouteTcpproxy() {
	for {
		tcpProxyResponse := <-r.Tcp.PersonaOutput

        golog.Debugf("<-- RouteTcpproxy: Persona <- Tcpproxy: %v", tcpProxyRequest)

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

        golog.Debugf("<-- RouteUdpproxy: Persona <- Udpproxy: %v", udpProxyRequest)

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

func (r *Router) RouteTimerProxy() {
	for {
		timerProxyResponse := <-r.Timer.PersonaOutput

        golog.Debugf("<-- RouteTimerProxy: Persona <- TimerProxy: %v", timerProxyRequest)

		messageData, dataError := timerProxyResponse.Data()
		if dataError != nil {
			golog.Debug(dataError.Error())
			continue
		}

		message := make([]byte, 0)
		message = append(message, byte(Timer))
		message = append(message, messageData...)

		r.PersonaWriteChannel <- message
	}
}
