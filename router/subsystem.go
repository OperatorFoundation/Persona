package main

type Subsystem byte

const (
	Client   Subsystem = 1
	Udpproxy Subsystem = 2
	Tcpproxy Subsystem = 3
    Timer    Subsystem = 4
)
