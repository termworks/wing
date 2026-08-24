## SSH option assembly and reachability probes shared by machine and sync.

import std/[hashes, net, os, osproc, posix, streams, strutils]

import ./storage
import ./types
import ./util

proc interfaceExists*(iface: string): bool =
  iface == "local" or not dirExists("/sys/class/net") or dirExists(
      "/sys/class/net" / iface)

proc parseHost*(value: string): Host =
  let parts = value.split(":")
  if parts.len == 0 or parts.len > 3:
    die("Invalid host format: " & value, 2)
  try:
    discard parseIpAddress(parts[0])
  except ValueError:
    die("Invalid ip format: " & parts[0], 2)
  result = Host(ip: parts[0], port: "22", iface: "local")
  if parts.len == 2:
    if parts[1].allCharsInSet({'0'..'9'}):
      result.port = parts[1]
    else:
      result.iface = parts[1]
  elif parts.len == 3:
    result.port = parts[1]
    result.iface = parts[2]
  try:
    let portNumber = parseInt(result.port)
    if portNumber < 1 or portNumber > 65535:
      die("Invalid port format: " & result.port, 2)
  except ValueError:
    die("Invalid port format: " & result.port, 2)
  if not interfaceExists(result.iface):
    die("Invalid iface name: " & result.iface, 2)

const maxSocketPath = 100
  ## A unix socket path is capped by the kernel at 108 bytes including the terminator, and ssh
  ## refuses outright rather than truncating: `ControlPath too long`. 100 leaves room for the
  ## `.<random>` suffix ssh appends while the master is starting up.

proc controlSocketPath*(machine: Machine; host: Host): string =
  ## Shared SSH ControlMaster socket so connect/check/sync reuse one connection.
  ##
  ## Under the data directory where it belongs -- unless that path is long enough to break ssh, in
  ## which case a short one under the runtime directory is better than every ssh command failing.
  ## A deep XDG_DATA_HOME is not exotic: a checkout under a long project path is enough.
  let dir = dataRoot() / "ssh"
  createDir(dir)
  let preferred = dir / (machine.name & "-" & host.iface)
  if preferred.len <= maxSocketPath:
    return preferred

  let runtime = getEnv("XDG_RUNTIME_DIR")
  let shortBase = if runtime.len > 0: runtime else: "/tmp"
  let shortDir = shortBase / ("wing-" & $getuid())
  createDir(shortDir)
  # Named by a hash of the full path, so two machines whose names collide after shortening still
  # get separate sockets -- and so the name stays the same between runs, which is what lets the
  # second connection reuse the first one's master.
  shortDir / (machine.name & "-" & host.iface & "-" &
      $(hash(preferred) and 0xffffff))

proc sshOptionArgs*(machine: Machine; host: Host): seq[string] =
  ## SSH options (key, port, ControlMaster reuse, proxy jump, agent forwarding)
  ## used by connect, check --ssh, and rsync's --rsh. Does NOT include the
  ## user@host target — callers append it, and rsync appends it from the dst.
  result = @["-o", "ControlMaster=auto",
             "-o", "ControlPath=" & controlSocketPath(machine, host),
             "-o", "ControlPersist=60",
             "-o", "BatchMode=no",
             "-o", "ServerAliveInterval=30"]
  if machine.key.len > 0:
    result.add(@["-i", machine.key])
  if host.port != "22":
    result.add(@["-p", host.port])
  if machine.proxyJump.len > 0:
    result.add(@["-J", machine.proxyJump])
  if machine.forwardAgent:
    result.add("-A")

proc shellDisplay*(command: string; args: seq[string]): string =
  result = command
  for arg in args:
    result.add(" " & quoteShell(arg))

proc sshReachable*(machine: Machine; host: Host; timeoutMs: int): tuple[
    ok: bool; detail: string] =
  ## Real SSH auth test: run `ssh <options> -o BatchMode=yes -o ConnectTimeout
  ## <user@host> true` and report whether auth succeeded.
  var args = sshOptionArgs(machine, host)
  let connectTimeout = max(1, timeoutMs div 1000)
  # Override BatchMode so the test never hangs on a password prompt.
  args.add(@["-o", "BatchMode=yes", "-o", "ConnectTimeout=" & $connectTimeout])
  args.add(machine.username & "@" & host.ip)
  args.add("true")
  try:
    let p = startProcess("ssh", args = args, options = {poUsePath,
        poStdErrToStdOut})
    let captured = p.outputStream.readAll()
    let code = p.waitForExit()
    p.close()
    result.ok = code == 0
    result.detail = if code == 0: "auth ok" else: "auth failed (exit " & $code &
        "): " & captured.strip()
  except CatchableError as e:
    result.ok = false
    result.detail = "ssh not available: " & e.msg

proc writeSshConfig*(machine: Machine) =
  for host in machine.hosts:
    echo "Host " & machine.name & "-" & host.iface
    echo "  HostName " & host.ip
    echo "  User " & machine.username
    echo "  Port " & host.port
    if machine.key.len > 0:
      echo "  IdentityFile " & machine.key
      echo "  IdentitiesOnly yes"
    echo "  StrictHostKeyChecking accept-new"
    echo "  ControlMaster auto"
    echo "  ControlPath " & controlSocketPath(machine, host)
    echo "  ControlPersist 60"
    if machine.proxyJump.len > 0:
      echo "  ProxyJump " & machine.proxyJump
    if machine.forwardAgent:
      echo "  ForwardAgent yes"
    echo ""

proc tcpReachable*(host: Host; timeoutMs: int): bool =
  var socket = newSocket()
  try:
    socket.connect(host.ip, Port(parseInt(host.port)), timeoutMs)
    result = true
  except CatchableError:
    result = false
  finally:
    socket.close()
