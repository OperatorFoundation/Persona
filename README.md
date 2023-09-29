# Persona

Persona is the server for the Moonbounce VPN. It is written in Go and Swift and runs on Linux.

## Architectural Overview

There are three components: frontend, router, and Persona.

frontend just handles accepting incoming connections and then passes each connection to the router.
router handles all concurrency, this includes talking to the client, Persona, and the upstream servers.
Persona handles the logic, this includes parsing and generating packets and managing the TCP state machine.

## Installing

You need the Swift compiler to be installed and in the PATH. Currently, Swift 5.8 is supported.
The install script is intended to be run on a fresh Ubuntu 22.04 installation with nothing else running on the system.
In order to use the systemd launcher for frontend, systemd already needs to have been installed prior to running the
install script.

While logged in as root:
```
cd /root
git clone https://github.com/OperatorFoundation/Persona
cd Persona
./install.sh
```

The install script installs the Go compiler and xinetd, builds Persona in release mode, builds frontend and router,
configures systemd to run frontend, configures the xinetd echo services for TCP and UDP, and configures the firewall.

* You must check out Persona as the root user into the /root diretory (the root user's home directory).
* ./install.sh and ./update.sh must be run as the root user from the /root/Persona directory.

The xinetd TCP and UDP echo services are used for testing. The echo server is blocked from remote access for security
reasons. Since the firewall blocks access, it can only be accessed locally, or through the Persona VPN. The Persona VPN
can be tested easily by connecting to the server IP on port 7 over either TCP or UDP.

## Running

A systemd service configuration is included. Therefore, there is no need to run it manually. After running the install
script, you can connect to the Persona port and systemd will automatically launch an instance of Persona.

## Updating

If you are working on developing Persona, there is an script called update.sh that will update to the latest
versiona and restart the Persona daemon.

## Pluggable Transport Support

Persona is designed to be run behind a Pluggable Transport server such as Shapeshifter Dispatcher. The dispatcher
takes care of encryption and obfuscation of the VPN connection.

