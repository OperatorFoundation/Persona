package tcpproxy

import (
	"frontend/ip"
	"github.com/kataras/golog"
)

type RequestType byte

const (
	RequestOpen  RequestType = 1
	RequestWrite RequestType = 2
	RequestClose RequestType = 3
)

type Request struct {
	Type     RequestType
	Identity *ip.Identity
	Data     []byte
}

func NewRequest(data []byte) *Request {
	golog.Debugf("tcpproxy.NewRequest(%d bytes)", len(data))

	if len(data) < 13 {
		return nil
	}

	typeByte := data[0]
	identityBytes := data[1:13]
	rest := data[13:]

	requestType := RequestType(typeByte)
	identity := ip.NewIdentity(identityBytes)

	switch requestType {
	case RequestOpen:
		return &Request{requestType, identity, nil}
	case RequestWrite:
		return &Request{requestType, identity, rest}
	case RequestClose:
		return &Request{requestType, identity, nil}
	default:
		return nil
	}
}
