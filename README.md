# Persona

Persona is the server for the Moonbounce VPN. It is written in Go and Swift and runs on Linux.

## Installing

You need the Swift compiler to be installed and in the PATH. Currently, Swift 5.8 is supported.
Persona runs as a daemon under systemd, so systemd needs to already be installed.

The install script is intended to be run on a fresh Ubuntu 22.04 installation with nothing else running on the system.

* You must check out Persona as the root user into the /root diretory (the root user's home directory).
* ./install.sh and ./update.sh must be run as the root user from the /root/Persona directory.

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

## Updating

If you are working on developing Persona, there is an script called update.sh that will update to the latest
versiona and restart the Persona daemon. Please note that this will not update dependencies, so use the usual
"swift package update" to update dependencies if they have changed and then run update.sh afterwards.

## Pluggable Transport Support

Persona is designed to be run behind a Pluggable Transport server such as Shapeshifter Dispatcher. The dispatcher
takes care of encryption and obfuscation of the VPN connection.

