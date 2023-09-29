package tcpproxy

import "router/ip"

type ResponseType byte

const (
	ResponseData           ResponseType = 1
	ResponseClose          ResponseType = 2
	ResponseError          ResponseType = 3
	ResponseConnectSuccess ResponseType = 4
	ResponseConnectFailure ResponseType = 5
)

type Response struct {
	Type     ResponseType
	Identity *ip.Identity
	Payload  []byte
	Error    error
}

func NewDataResponse(identity *ip.Identity, payload []byte) *Response {
	return &Response{ResponseData, identity, payload, nil}
}

func NewCloseResponse(identity *ip.Identity) *Response {
	return &Response{ResponseClose, identity, nil, nil}
}

func NewErrorResponse(identity *ip.Identity, responseError error) *Response {
	return &Response{ResponseError, identity, nil, responseError}
}

func NewConnectSuccessResponse(identity *ip.Identity) *Response {
	return &Response{ResponseConnectSuccess, identity, nil, nil}
}

func NewConnectFailureResponse(identity *ip.Identity) *Response {
	return &Response{ResponseConnectFailure, identity, nil, nil}
}

func (r *Response) Data() ([]byte, error) {
	result := make([]byte, 0)

	typeByte := byte(r.Type)
	identityBytes := r.Identity.Data

	result = append(result, typeByte)
	result = append(result, identityBytes...)

	// Only these two types have additional data and require additional handling, all other types are covered by the code above.
	switch r.Type {
	case ResponseData:
		if r.Payload != nil {
			result = append(result, r.Payload...)
		}
	case ResponseError:
		if r.Error != nil {
			result = append(result, []byte(r.Error.Error())...)
		}
	}

	return result, nil
}
