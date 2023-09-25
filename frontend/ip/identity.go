package ip

import (
	"errors"
	"strings"
)

type Identity struct {
	Data        []byte
	Source      string
	Destination string
}

func NewIdentity(data []byte) *Identity {
	if len(data) != 12 {
		return nil
	}

	sourceBytes := data[:6]
	destinationBytes := data[6:]

	source := AddressBytesToString(sourceBytes)
	destination := AddressBytesToString(destinationBytes)

	return &Identity{data, source, destination}
}

func NewIdentityFromString(identityString string) (*Identity, error) {
	parts := strings.Split(identityString, ":")
	if len(parts) != 4 {
		return nil, errors.New("error, identity string did not contain the right number of : separators")
	}

	sourceAddressString := parts[0]
	sourcePortString := parts[1]
	destinationAddressString := parts[2]
	destinationPortString := parts[3]

	sourceBytes, sourceError := StringToAddressBytes(sourceAddressString + ":" + sourcePortString)
	if sourceError != nil {
		return nil, sourceError
	}

	destinationBytes, destinationError := StringToAddressBytes(destinationAddressString + ":" + destinationPortString)
	if destinationError != nil {
		return nil, destinationError
	}

	identityBytes := make([]byte, 0)
	identityBytes = append(identityBytes, sourceBytes...)
	identityBytes = append(identityBytes, destinationBytes...)
	identity := NewIdentity(identityBytes)
	return identity, nil
}

func (i *Identity) String() string {
	return i.Source + ":" + i.Destination
}
