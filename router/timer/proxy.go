package timer

import (
	"github.com/kataras/golog"
	"time"
)

/*
The timer subsystem handles TCP retransmission timers for Persona.
When a new timer subsystem message is received from Persona, if there is not such timer then a new
timer is set. If there is an existing timer, it is reset.
When a timer fires, a response is sent to Persona.
There is no way to cancel timers, as there is no need to do so.
Timers that fire for segments that have already been acked are ignored by Persona.
*/

var TcpRetransmissionTimeout = time.Duration(time.Duration.Seconds(6)) // 3 seconds

type Proxy struct {
	Timers        map[string]*time.Timer
	PersonaInput  chan *Request
	PersonaOutput chan *Response
}

func New() *Proxy {
	timers := make(map[string]*time.Timer)
	input := make(chan *Request)
	output := make(chan *Response)

	return &Proxy{timers, input, output}
}

func (p *Proxy) Run() {
	golog.Debug("timer.Proxy.Run()")
	for {
		golog.Debug("timer.Proxy.Run - main loop, waiting for message on channel input")
		// Read a new timer request. A timer request either sets a new timer or resets an existing timer.
		request := <-p.PersonaInput
		golog.Debug("timer.Proxy.Run - PersonaInput")
		golog.Debug("timer.Proxy.Run - RequestOpen")
		timer, ok := p.Timers[request.Identity.String()]
		if ok {
			timer.Reset(TcpRetransmissionTimeout)
			continue
		} else {
			timer := time.NewTimer(TcpRetransmissionTimeout)
			golog.Debugf("new timer for %s, %v : %v", request.Identity, TcpRetransmissionTimeout, time.Now().Unix())
			p.Timers[request.Identity.String()] = timer

			// Start a goroutine to wait on the time.
			go func() {
				// Wait for the timer to fire by reading from the timer's channel.
				<-timer.C
				golog.Debugf("timer trigger for %s, %v : %v", request.Identity, TcpRetransmissionTimeout, time.Now().Unix())

				// Send a timer firing message to Persona. Persona will ignore timers that are out of date.
				p.PersonaOutput <- NewResponse(request.Identity, request.LowerBound)
			}()
		}
	}
}
