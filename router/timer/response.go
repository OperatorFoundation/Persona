package timer

import (
	"encoding/binary"
	"router/ip"
)

type Response struct {
	Identity   *ip.Identity
	LowerBound uint32
}

func NewResponse(identity *ip.Identity, lowerBound uint32) *Response {
	return &Response{identity, lowerBound}
}

func (r *Response) Data() ([]byte, error) {
	sequenceNumberBytes := make([]byte, 4)
	binary.BigEndian.PutUint32(sequenceNumberBytes, r.LowerBound)

	result := make([]byte, 0)
	result = append(result, r.Identity.Data...)
	result = append(result, sequenceNumberBytes...)

	return result, nil
}
