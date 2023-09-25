package ip

import (
	"encoding/binary"
	"errors"
	"net"
	"strconv"
	"strings"
)

func AddressBytesToString(data []byte) string {
	hostBytes := data[0:4]
	portBytes := data[4:6]
	hostString := net.IP{hostBytes[0], hostBytes[1], hostBytes[2], hostBytes[3]}.String()
	portString := strconv.Itoa(int(binary.BigEndian.Uint16(portBytes)))
	return hostString + ":" + portString
}

func StringToAddressBytes(input string) ([]byte, error) {
	parts := strings.Split(input, ":")
	if len(parts) != 2 {
		return nil, errors.New("error, address did not contain : separator")
	}

	hostString := parts[0]
	portString := parts[1]

	hostIP, resolveError := net.ResolveIPAddr("ip", hostString)
	if resolveError != nil {
		return nil, resolveError
	}
	hostBytes := hostIP.IP

	portInt, portError := strconv.Atoi(portString)
	if portError != nil {
		return nil, portError
	}
	portUint16 := uint16(portInt)
	portBytes := make([]byte, 2)
	binary.BigEndian.PutUint16(portBytes, portUint16)

	result := make([]byte, 0)
	result = append(result, hostBytes...)
	result = append(result, portBytes...)
	return result, nil
}
