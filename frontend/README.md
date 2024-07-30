### The Operator Foundation

[Operator](https://operatorfoundation.org) makes usable tools to help people around the world with censorship, security,
and privacy.

## The Moonbounce Project
The Moonbounce Project is an initiative covering several clients, servers, and libraries. The goal of the project is to
provide a simple VPN service that integrates Pluggable Transport technology. This allows the Moonbounce VPN to operate
on network with restrictive Internet censorship that blocks VPN protocols such as OpenVPN and Wireguard. This project is
part of Persona, one of several components of the Moonbounce project.

# Persona

Persona is the server for the Moonbounce VPN. It is written in Go and Swift and runs on Linux under systemd.

## frontend

frontend is the outward-facing component of Persona. It listens on a socket and forks router processes for each
incoming connection. It is similar in operation to inetd, xinetd, or systemd socket services. frontend was written
to replace the use of systemd socket services for Persona because under empirical testing the systemd socket service
implementation was acting as a performance bottleneck. frontend is still intended to be run under systemd, but just
as a normal service. This also makes it easier for development because you can run it manually or through a different
init system. While written for Linux and not tested on other platforms, it should generally be cross-platform.

While frontend is only intended for use with Persona, there is a general-purpose rewrite of frontend under development called
[jumpgate](https://github.com/blanu/jumpgate/blob/main/main.go).