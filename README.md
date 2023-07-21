# Persona

Persona is the server for the Moonbounce VPN. It is written in Swift and runs on Linux.

## Installing

This is experimental software and is still under development.
You need the Swift compiler to be installed and in the PATH.
Persona runs as a daemon under systemd, so systemd needs to already be installed.
The install script is intended to be run on a fresh Ubuntu 22.04 installation with nothing else running on the system.

```
git clone https://github.com/OperatorFoundation/Persona
cd Persona
./install.sh
```

The install script does the following things:
- Update Persona source from git
- Build Persona from source
- Configure systemd to run Persona as a daemon and start the daemon
- Install xinetd
- Configure xinetd to run TCP and UDP echo servers, for testing purposes
- Configure the ufw firewall to allow access to SSH and Persona and disallow remote access to the echo server.
- Enable the ufw firewall.

The echo server is blocked from remote access for security reasons. Since the firewall blocks access, it can
only be accessed locally, or through the Persona VPN. The Persona VPN can be tested easily by connecting to the
server IP on port 7 over either TCP or UDP.

## Running

Persona runs as a daemon under systemd. Therefore, there is no need to run it manually. After running the install
script, you can connect to the Persona port and systemd will automatically launch an instance of Persona.

## Pluggable Transport Support

Persona is designed to be run behind a Pluggable Transport server such as Shapeshifter Dispatcher. The dispatcher
takes care of encryption and obfuscation of the VPN connection.

