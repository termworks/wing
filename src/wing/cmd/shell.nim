## `wing ssh` — a shell on a machine, or inside a project wherever it lives.
##
## `wing machine connect` already opened a shell on a machine. What it could not do is the thing
## anyone actually wants next: land in the directory the work is in. Once the registry knows which
## machine a project is on, "ssh me into that project" is one lookup and one `cd`, and it is the
## same command whether the project turns out to be on this machine or another one.

import std/[os, osproc, strutils]

import ../cliargs
import ../projects/locate
import ../remote
import ../ssh
import ../store/machines
import ../store/projects
import ../types
import ../util

proc findMachine*(machines: seq[Machine]; name: string): Machine =
  for machine in machines:
    if machine.name == name:
      return machine
  die("Machine '" & name & "' not found", 2)

proc loginArgs(machine: Machine; host: Host; directory, command: string): seq[string] =
  ## The ssh argv for an interactive session, optionally starting somewhere.
  ##
  ## `-t` forces a tty because the remote side is a login shell and without one it comes up with no
  ## prompt, no job control and no line editing -- which looks like a broken shell rather than a
  ## missing flag.
  result = sshOptionArgs(machine, host)
  result.add("-t")
  result.add(if machine.username.len > 0: machine.username & "@" &
      host.ip else: host.ip)
  if directory.len == 0 and command.len == 0:
    return

  # `exec $SHELL -l` rather than plain `$SHELL`: the login shell replaces this one, so the session
  # ends when the user exits it rather than falling back to a second shell in the home directory.
  var remote = ""
  if directory.len > 0:
    remote.add("cd " & quoteShell(directory) & " && ")
  remote.add(if command.len > 0: command else: "exec \"${SHELL:-/bin/sh}\" -l")
  result.add(remote)

proc runInteractive(machine: Machine; host: Host; directory, command: string;
    dryRun: bool) =
  let argv = loginArgs(machine, host, directory, command)
  if dryRun:
    echo shellDisplay("ssh", argv)
    return
  # The ssh process inherits this terminal, so it is a session rather than captured output -- and
  # wing exits with whatever ssh exited with, so a failed connection is a failed command.
  let process = startProcess("ssh", args = argv,
      options = {poUsePath, poParentStreams})
  let code = process.waitForExit()
  process.close()
  quit(code)

proc handleSsh*(argsIn: seq[string]) =
  ## `wing ssh lab`, `wing ssh api`, `wing ssh lab:api`, `wing ssh lab -- uptime`.
  ##
  ## One argument, and it may be a machine or a project: those are the two things anyone means by
  ## "ssh into it", and asking which one it was is a question wing can answer by looking.
  var args = argsIn
  let dryRun = popFlag(args, ["--dry-run", "--print-command"])
  let iface = popValue(args, ["-i", "--interface"])
  let asMachine = popFlag(args, ["-m", "--machine"])
  let asProject = popFlag(args, ["-p", "--project"])
  let atPath = popValue(args, ["-C", "--cd"])

  var command = ""
  let separator = args.find("--")
  if separator >= 0:
    command = args[separator + 1 .. ^1].join(" ")
    args = args[0 ..< separator]
  rejectUnknownOptions(args)
  requireArgs(args, 1,
      "wing ssh NAME [--project|--machine] [--cd DIR] [-- COMMAND]")
  let reference = args[0]

  let machines = parseMachines(ensureMachinesFile())
  let projects = parseProjects(ensureProjectsFile())

  # A machine wins a bare name, because `wing ssh lab` reads as a machine and a project sharing that
  # name is the rarer case -- `--project` says otherwise, and `machine:project` is never ambiguous.
  if not asProject and not reference.contains(':'):
    for machine in machines:
      if machine.name == reference:
        var host = firstHost(machine)
        if iface.len > 0:
          var found = false
          for candidate in machine.hosts:
            if candidate.iface == iface:
              host = candidate
              found = true
              break
          if not found:
            die("Machine '" & reference & "' has no interface '" & iface & "'", 2)
        if host.ip.len == 0:
          die("Machine '" & reference & "' has no address", 2)
        runInteractive(machine, host, atPath, command, dryRun)
        return

  if asMachine:
    die("Machine '" & reference & "' not found", 2)

  let matches = locate(projects, reference)
  if matches.len == 0:
    die("No machine or project called '" & reference & "'", 2)
  if matches.len > 1:
    die(describeAmbiguity(matches), 2)
  let project = matches[0].project
  let directory = if atPath.len > 0: atPath else: project.path

  if not isRemote(project):
    # Already here. Exec a login shell in the directory rather than printing the path: the command
    # said "put me in the project", and on this machine that is a shell, not a string.
    # A dry run prints what would happen and touches nothing, so it does not care whether the
    # directory is there -- and asking about a path on this machine is exactly how you find out it
    # has moved.
    if dryRun:
      echo "cd " & quoteShell(directory) & " && exec $SHELL -l"
      return
    if not dirExists(directory):
      die("'" & project.name & "' is at " & directory &
          ", which does not exist", 2)
    setCurrentDir(directory)
    let shell = getEnv("SHELL", "/bin/sh")
    if command.len > 0:
      quit(execShellCmd(command))
    quit(execShellCmd(shell & " -l"))

  let machine = findMachine(machines, project.machine)
  let host = firstHost(machine)
  if host.ip.len == 0:
    die("Machine '" & machine.name & "' has no address", 2)
  runInteractive(machine, host, directory, command, dryRun)

proc handleWhere*(argsIn: seq[string]) =
  ## `wing where NAME` — the one line a shell function needs: `cd "$(wing where api)"` when it is
  ## local, and the ssh command when it is not. Printing is the point; nothing is entered.
  var args = argsIn
  rejectUnknownOptions(args)
  requireArgs(args, 1, "wing where PROJECT")
  let projects = parseProjects(ensureProjectsFile())
  let matches = locate(projects, args[0])
  if matches.len == 0:
    die("No project called '" & args[0] & "'", 2)
  if matches.len > 1:
    die(describeAmbiguity(matches), 2)
  let project = matches[0].project
  if isRemote(project):
    let machines = parseMachines(ensureMachinesFile())
    let machine = findMachine(machines, project.machine)
    let host = firstHost(machine)
    echo shellDisplay("ssh", loginArgs(machine, host, project.path, ""))
  else:
    echo project.path
