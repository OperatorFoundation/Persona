package timer

import "router/ip"
import "encoding/binary"

type Request struct {
	Identity   *ip.Identity
	LowerBound uint32
}

func NewRequest(data []byte) *Request {
	if len(data) < 16 {
		return nil
	}

	identityBytes := data[0:12]
	rest := data[12:]

	identity := ip.NewIdentity(identityBytes)

	sequenceNumber := binary.BigEndian.Uint32(rest)

	return &Request{identity, sequenceNumber}
}
