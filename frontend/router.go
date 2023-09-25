package main

import (
	"errors"
	"frontend/tcpproxy"
	"frontend/udpproxy"
	"log"
)

type Router struct {
	Tcp *tcpproxy.Proxy
	Udp *udpproxy.Proxy

	ClientReadChannel  chan []byte
	ClientWriteChannel chan []byte

	PersonaReadChannel  chan []byte
	PersonaWriteChannel chan []byte

	TcpProxyWriteChannel chan *tcpproxy.Request
	TcpProxyReadChannel  chan *tcpproxy.Response

	UdpProxyWriteChannel chan *udpproxy.Request
	UdpProxyReadChannel  chan *udpproxy.Response
}

func NewRouter(clientRead chan []byte, clientWrite chan []byte, personaRead chan []byte, personaWrite chan []byte) (*Router, error) {
	tcp := tcpproxy.New()
	if tcp == nil {
		return nil, errors.New("could not initialize TCP proxy")
	}

	udp := udpproxy.New()
	if udp == nil {
		return nil, errors.New("could not initialize UDP proxy")
	}

	tcpWrite := make(chan *tcpproxy.Request)
	tcpRead := make(chan *tcpproxy.Response)

	udpWrite := make(chan *udpproxy.Request)
	udpRead := make(chan *udpproxy.Response)

	return &Router{tcp, udp, clientRead, clientWrite, personaRead, personaWrite, tcpWrite, tcpRead, udpWrite, udpRead}, nil
}

func (r *Router) Route() {
	for {
		select {
		// Received data from the client
		case clientData := <-r.ClientReadChannel:
			// Forward data to Persona
			message := make([]byte, 0)
			message = append(message, byte(Client))
			message = append(message, clientData...)

			r.PersonaWriteChannel <- message

		case personaData := <-r.PersonaReadChannel:
			if len(personaData) < 1 {
				log.Println("error, personaData was empty")
				continue
			}

			subsystem := Subsystem(personaData[0])
			data := personaData[1:]

			switch subsystem {
			case Client:
				r.ClientWriteChannel <- data
			case Udpproxy:
				request := udpproxy.NewRequest(data)
				if request == nil {
					log.Println("error, bad request")
					continue
				} else {
					r.UdpProxyWriteChannel <- request
				}
			case Tcpproxy:
				request := tcpproxy.NewRequest(data)
				if request == nil {
					log.Println("error, bad request")
					continue
				} else {
					r.TcpProxyWriteChannel <- request
				}
			default:
				log.Println("bad message type")
			}

		case tcpProxyResponse := <-r.TcpProxyReadChannel:
			switch tcpProxyResponse.Type {
			case tcpproxy.ResponseData:
				messageData, dataError := tcpProxyResponse.Data()
				if dataError != nil {
					log.Println(dataError.Error())
					continue
				}

				message := make([]byte, 0)
				message = append(message, byte(Tcpproxy))
				message = append(message, messageData...)

				r.PersonaWriteChannel <- message

			case tcpproxy.ResponseClose:
				messageData, dataError := tcpProxyResponse.Data()
				if dataError != nil {
					log.Println(dataError.Error())
					continue
				}

				message := make([]byte, 0)
				message = append(message, byte(Tcpproxy))
				message = append(message, messageData...)

				r.PersonaWriteChannel <- message

			case tcpproxy.ResponseError:
				if tcpProxyResponse.Error != nil {
					log.Println(tcpProxyResponse.Error.Error())

					closeResponse := tcpproxy.NewCloseResponse(tcpProxyResponse.Identity)

					messageData, dataError := closeResponse.Data()
					if dataError != nil {
						log.Println(dataError.Error())
						continue
					}

					message := make([]byte, 0)
					message = append(message, byte(Tcpproxy))
					message = append(message, messageData...)

					r.PersonaWriteChannel <- message
				}
			}

		case udpProxyResponse := <-r.UdpProxyReadChannel:
			switch udpProxyResponse.Type {
			case udpproxy.ResponseData:
				messageData, dataError := udpProxyResponse.Data()
				if dataError != nil {
					log.Println(dataError.Error())
					continue
				}

				message := make([]byte, 0)
				message = append(message, byte(Tcpproxy))
				message = append(message, messageData...)

				r.PersonaWriteChannel <- message

			case udpproxy.ResponseClose:
				messageData, dataError := udpProxyResponse.Data()
				if dataError != nil {
					log.Println(dataError.Error())
					continue
				}

				message := make([]byte, 0)
				message = append(message, byte(Tcpproxy))
				message = append(message, messageData...)

				r.PersonaWriteChannel <- message

			case udpproxy.ResponseError:
				if udpProxyResponse.Error != nil {
					log.Println(udpProxyResponse.Error.Error())

					closeResponse := tcpproxy.NewCloseResponse(udpProxyResponse.Identity)

					messageData, dataError := closeResponse.Data()
					if dataError != nil {
						log.Println(dataError.Error())
						continue
					}

					message := make([]byte, 0)
					message = append(message, byte(Tcpproxy))
					message = append(message, messageData...)

					r.PersonaWriteChannel <- message
				}
			}
		}
	}
}
