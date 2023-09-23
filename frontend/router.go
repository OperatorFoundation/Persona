package main

type Router struct {
	ClientReadChannel  chan []byte
	ClientWriteChannel chan []byte

	PersonaReadChannel  chan []byte
	PersonaWriteChannel chan []byte
}

func (r Router) Route() {
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
				print("error, personaData was empty")
				continue
			}

			subsystem := Subsystem(personaData[0])
			data := personaData[1:]

			switch subsystem {
			case Client:
				r.ClientWriteChannel <- data
			case Udpproxy:
				print("unimplemented udpproxy support")
			case Tcpproxy:
				print("unimplemented tcpproxy support")
			default:
				print("bad message type")
			}
		}
	}
}
