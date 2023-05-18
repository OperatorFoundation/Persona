# Persona

Part of the Discovery Service.

Persona can be used to run a server that speaks the [Flower](https://github.com/OperatorFoundation/Flower.git) protocol. It has been written in Swift and can be run on both macOS and Linux.

### To generate new client / server configs ###

Persona uses the 'ArgumentParser' library to parse and execute command line arguments.

From the Persona directory in your macOS / Linux command line terminal;

• To see what subcommands you have available to you:

```
$ swift run
```

```
example print out
USAGE: Persona <subcommand>

OPTIONS:
  -h, --help              Show help information.

SUBCOMMANDS:
  new
  run

  See 'Persona help <subcommand>' for detailed help.
```
===

• To create new client / server configs:

```
$ swift run Persona new <exampleConfigName> <port> <ip>
```

```
Wrote config to ~/persona-server.json
Wrote config to ~/persona-client.json
```
===

• To run the server:

```
$ swift run Persona run
```

```
...
listening on 127.0.0.1 2121
Waiting to accept a connection
...
```
