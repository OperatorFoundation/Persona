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

	return &Router{tcp, udp, clientRead, clientWrite, personaRead, personaWrite}, nil
}

func (r *Router) Route() {
	log.Println("Router.Route()")
	for {
		log.Println("Router.Route - main loop")
		select {
		// Received data from the client
		case clientData := <-r.ClientReadChannel:
			log.Println("Router.Route - ClientReadChannel")
			// Forward data to Persona
			message := make([]byte, 0)
			message = append(message, byte(Client))
			message = append(message, clientData...)

			r.PersonaWriteChannel <- message

		case personaData := <-r.PersonaReadChannel:
			log.Println("Router.Route - PersonaReadChannel")
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
					log.Println("error, bad udpproxy request")
					continue
				} else {
					r.Udp.PersonaInput <- request
				}
			case Tcpproxy:
				request := tcpproxy.NewRequest(data)
				if request == nil {
					log.Println("error, bad tcpproxy request")
					continue
				} else {
					log.Println("sending Persona request to tcpproxy")
					r.Tcp.PersonaInput <- request
					log.Println("sent Persona request to tcpproxy")
				}
			default:
				log.Println("bad message type")
			}

		case tcpProxyResponse := <-r.Tcp.PersonaOutput:
			log.Println("Router.Route - TcpProxyReadChannel")
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

		case udpProxyResponse := <-r.Udp.PersonaOutput:
			log.Println("Router.Route - UdpProxyReadChannel")
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
