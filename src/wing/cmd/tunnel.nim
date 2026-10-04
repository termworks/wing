## `wing machine tunnel` — port forwards you can name, and an ssh config every other tool can read.
##
## A forward is three numbers and a host, typed correctly, every time you need it. Naming one is the
## difference between remembering `-L 5433:localhost:5432` and typing `wing machine tunnel start db`.
##
## The config export is the other half of the same idea: everything wing knows about reaching a
## machine, written where ssh, scp, rsync and git will find it, so those tools work on a machine
## wing registered without wing being in the way.

import std/[os, osproc, posix, strutils]

import ../cliargs
import ../remote
import ../ssh
import ../storage
import ../store/machines
import ../toml
import ../types
import ../util

type
  Tunnel* = object
    name*: string
    machine*: string
    kind*: string ## local, remote or dynamic
    spec*: string ## what follows -L, -R or -D

proc tunnelsFile*(): string =
  configPath("tunnels.toml")

proc parseTunnels*(path: string): seq[Tunnel] =
  let content = readConfig(path)
  var current = -1
  for rawLine in content.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith("#"):
      continue
    if line == "[[tunnels]]":
      result.add(Tunnel(kind: "local"))
      current = result.high
    elif current >= 0 and line.contains("="):
      let (key, value) = splitKeyValue(line)
      case key
      of "name": result[current].name = unquoteToml(value)
      of "machine": result[current].machine = unquoteToml(value)
      of "kind": result[current].kind = unquoteToml(value)
      of "spec": result[current].spec = unquoteToml(value)
      else: discard

proc writeTunnels*(path: string; tunnels: seq[Tunnel]) =
  var text = schemaHeader()
  if tunnels.len == 0:
    text.add("tunnels = []\n")
  else:
    for tunnel in tunnels:
      text.add("[[tunnels]]\n")
      text.add("name = " & tomlString(tunnel.name) & "\n")
      text.add("machine = " & tomlString(tunnel.machine) & "\n")
      text.add("kind = " & tomlString(tunnel.kind) & "\n")
      text.add("spec = " & tomlString(tunnel.spec) & "\n\n")
  atomicWriteFile(path, text)

proc pidFile(name: string): string =
  dataRoot() / "tunnels" / (name & ".pid")

proc runningPid(name: string): int =
  ## The pid if that tunnel is up, 0 otherwise. A pid file whose process is gone is stale and is
  ## treated as "not running" rather than believed.
  let file = pidFile(name)
  if not fileExists(file):
    return 0
  let pid = try: parseInt(readFile(file).strip()) except ValueError: 0
  if pid <= 0:
    return 0
  # The syscall rather than `kill -0` through a shell: it is one call instead of a process, and it
  # cannot be confused by whatever the shell decides an exit status means.
  if kill(Pid(pid), 0) != 0:
    removeFile(file)
    return 0
  pid

proc flagFor(tunnel: Tunnel): string =
  case tunnel.kind
  of "remote": "-R"
  of "dynamic": "-D"
  else: "-L"

proc findTunnel(tunnels: seq[Tunnel]; name: string): int =
  result = -1
  for i, tunnel in tunnels:
    if tunnel.name == name:
      return i

proc showHelp() =
  echo """
Usage: wing machine tunnel <COMMAND>

  add NAME MACHINE --local  LPORT:HOST:RPORT   forward a local port to the machine's side
  add NAME MACHINE --remote RPORT:HOST:LPORT   forward a port on the machine to here
  add NAME MACHINE --dynamic PORT              a SOCKS proxy through the machine
  list
  start NAME [--foreground]
  stop NAME
  remove NAME
"""

proc handleTunnel*(argsIn: seq[string]) =
  var args = argsIn
  if args.len == 0 or popFlag(args, ["-h", "--help"]):
    showHelp()
    return
  let command = args[0]
  args.delete(0)
  let path = tunnelsFile()
  ensureFile(path, schemaHeader() & "tunnels = []\n")
  var tunnels = parseTunnels(path)

  case command
  of "add", "new":
    let localSpec = popValue(args, ["-L", "--local"])
    let remoteSpec = popValue(args, ["-R", "--remote"])
    let dynamicSpec = popValue(args, ["-D", "--dynamic"])
    rejectUnknownOptions(args)
    requireArgs(args, 2, "wing machine tunnel add NAME MACHINE --local LPORT:HOST:RPORT")
    var kind = "local"
    var spec = localSpec
    if remoteSpec.len > 0:
      kind = "remote"
      spec = remoteSpec
    elif dynamicSpec.len > 0:
      kind = "dynamic"
      spec = dynamicSpec
    if spec.len == 0:
      die("Say what to forward: --local, --remote or --dynamic", 2)
    if findTunnel(tunnels, args[0]) >= 0:
      die("Tunnel '" & args[0] & "' already exists", 2)
    tunnels.add(Tunnel(name: args[0], machine: args[1], kind: kind, spec: spec))
    writeTunnels(path, tunnels)
    echo "Added tunnel '" & args[0] & "'"

  of "list", "ls", "l":
    rejectUnknownOptions(args)
    if tunnels.len == 0:
      echo "No tunnels. Add one with: wing machine tunnel add NAME MACHINE --local 8080:localhost:80"
      return
    var rows: seq[seq[string]]
    for tunnel in tunnels:
      let pid = runningPid(tunnel.name)
      rows.add(@[tunnel.name, tunnel.machine, tunnel.kind, tunnel.spec,
          if pid > 0: paint("up", "32") & " (" & $pid & ")" else: "down"])
    echo table(@["Name", "Machine", "Kind", "Forward", "State"], rows)

  of "start", "up":
    let foreground = popFlag(args, ["--foreground", "-f"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing machine tunnel start NAME")
    let idx = findTunnel(tunnels, args[0])
    if idx < 0:
      die("Tunnel '" & args[0] & "' not found", 2)
    if runningPid(args[0]) > 0:
      die("Tunnel '" & args[0] & "' is already up", 2)
    let tunnel = tunnels[idx]
    var machine: Machine
    var found = false
    for candidate in parseMachines(ensureMachinesFile()):
      if candidate.name == tunnel.machine:
        machine = candidate
        found = true
        break
    if not found:
      die("Machine '" & tunnel.machine & "' not found", 2)
    let host = firstHost(machine)
    if host.ip.len == 0:
      die("Machine '" & tunnel.machine & "' has no address", 2)

    # A tunnel gets its own connection, overriding the shared ControlMaster: with multiplexing on,
    # the forward is handed to the persistent master and *this* process exits -- leaving a working
    # tunnel that `list` reports as down and `stop` cannot stop, because the pid it recorded is
    # already gone. ssh takes the first value it sees for an option, so these must come first.
    var argv = @["-o", "ControlMaster=no", "-o", "ControlPath=none"] &
        sshOptionArgs(machine, host)
    argv.add(@[flagFor(tunnel), tunnel.spec])
    # -N carries no command and -T asks for no terminal: this connection exists to hold the
    # forward open, and a shell on the far side would be one more thing to notice and close.
    argv.add(@["-N", "-T"])
    argv.add(if machine.username.len > 0: machine.username & "@" &
        host.ip else: host.ip)
    if foreground:
      echo shellDisplay("ssh", argv)
      quit(execCmd("ssh " & argv.join(" ")))
    createDir(parentDir(pidFile(tunnel.name)))
    let process = startProcess("ssh", args = argv, options = {poUsePath})
    writeFile(pidFile(tunnel.name), $process.processID)
    echo "Tunnel '" & tunnel.name & "' is up: " & flagFor(tunnel) & " " &
        tunnel.spec & " via " & tunnel.machine & "  (pid " &
            $process.processID & ")"

  of "stop", "down":
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing machine tunnel stop NAME")
    let pid = runningPid(args[0])
    if pid == 0:
      die("Tunnel '" & args[0] & "' is not up", 2)
    discard kill(Pid(pid), SIGTERM)
    removeFile(pidFile(args[0]))
    echo "Tunnel '" & args[0] & "' stopped"

  of "remove", "rm", "delete":
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing machine tunnel remove NAME")
    let idx = findTunnel(tunnels, args[0])
    if idx < 0:
      die("Tunnel '" & args[0] & "' not found", 2)
    if runningPid(args[0]) > 0:
      die("Tunnel '" & args[0] & "' is up; stop it first", 2)
    tunnels.delete(idx)
    writeTunnels(path, tunnels)
    echo "Removed tunnel '" & args[0] & "'"

  else:
    die("Unknown tunnel command: " & command, 2)
