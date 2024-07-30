### The Operator Foundation

[Operator](https://operatorfoundation.org) makes useable tools to help people around the world with censorship, security, and privacy.

## The Moonbounce Project
The Moonbounce Project is an initiative covering several clients, servers, and libraries. The goal of the project is to provide a simple VPN service that integrates
Pluggable Transport technology. This allows the Moonbounce VPN to operate on network with restrictive Internet censorship that blocks VPN protocols such as OpenVPN
and Wireguard. This project, Persona, is one of several components of the Moonbounce project.

# Persona

Persona is the server for the Moonbounce VPN. It is written in Go and Swift and runs on Linux under systemd.

## Architectural Overview

There are three components: frontend, router, and Persona.

frontend handles accepting incoming connections and then passes each connection to the router.
router handles all concurrency, this includes talking to the client, Persona, and the upstream servers.
Persona handles the logic, this includes parsing and generating packets and managing the TCP state machine.

## Installing

You can of course copy pre-compiled binaries to your servers, as long as all of the correct runtime libraries are installed.
The methodology detailed here involves compiling the binaries directly on the deployment machine, which will also have
the effect of installing all of the necessary runtime libraries.

The provided install.sh script is intended to be run on an Ubuntu 22.04 installation. There is some setup necessary before running the install.sh script.
In particular, you need systemd installed and you need the Swift 5.8 compiler installed and in your PATH. Follow the instructions in [swift.org](https://swift.org/)
to install the Swift compiler for Ubuntu 22.04.

The install script performs the following functions:
- update the Persona git repository
- compile Persona
- move the Persona binaries to a convenient location
- install the Go compiler
- compile frontend
- compile router
- clean up old files from previous iterations of the project
- install the systemd configuration files
- start/restart the frontend under systemd
- install the xinetd echo servers (TCP and UDP) for testing purposes
- configure the firewall to allow remote access to ssh and the frontend, while denying remote access to the echo servers (they are only available through the VPN)

You only need to run the install.sh script once, or on a major update of the project. For incremental updates, you can run the update.sh script, which does the following:
- update the Persona git repository
- recompile Persona
- move the Persona binaries to a convenient location
- install the Go compiler
- compile frontend
- compile router
- restart the frontend under systemd aggressively, killing off any zombie processes that may have accumulated (just in case of bugs, in normal operation it should not be necessary)

To run the install.sh script, while logged in as root:
```
cd /root
git clone https://github.com/OperatorFoundation/Persona
cd Persona
./install.sh
```

* You must check out Persona as the root user into the /root diretory (the root user's home directory).
* ./install.sh and ./update.sh must be run as the root user from the /root/Persona directory.

The xinetd TCP and UDP echo services are used for testing. The echo server is blocked from remote access for security
reasons. Since the firewall blocks access, it can only be accessed locally, or through the Persona VPN. The Persona VPN
can be tested easily by connecting to the server IP on port 7 over either TCP or UDP. Please note that the echo servers are running on the Persona server and so are only
accessible when running without Pluggable Transports enabled.

## Running

A systemd service configuration is included. Therefore, there is no need to run it manually. After running the install
script, you can connect to the Persona port and systemd will automatically launch an instance of Persona.

### Getting .pcap's for Debugging

Edit the frontend.service file to turn on packet capture functionality.

`$ nano /etc/systemd/system/frontend.service`

Update the ExecStart line to include the -writePcap flag.

```
# frontend.service

 [Unit]
 Description = frontend server
 StartLimitIntervalSec=500
 StartLimitBurst=5

 [Service]
 Restart=on-failure
 RestartSec=5s
 ExecStart=/root/go/bin/frontend -writePcap

 [Install]
 WantedBy = multi-user.target
```

Restart the service.

```
$ systemctl daemon-reload
$ systemctl restart frontend
```
The file can be found in the project directory: Persona/persona.pcap

## Updating

If you are working on developing Persona, there is an script called update.sh that will update to the latest
versiona and restart the Persona daemon.

## Pluggable Transport Support

Persona is designed to be run behind a Pluggable Transport server such as Shapeshifter Dispatcher. The dispatcher
takes care of encryption and obfuscation of the VPN connection.

