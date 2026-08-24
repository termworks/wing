## `wing machine` — SSH host registry, config emission, and health checks.

import std/[os, osproc, sequtils, strutils]

import ../cliargs
import ../jsonfmt
import ./machine_remote
import ../ssh
import ../machines/facts
import ../projects/locate
import ../store/machines
import ../store/projects
import ../types
import ../util

proc showMachineHelp() =
  echo """
Usage: wing machine <COMMAND>

Commands:
  add NAME IP[:PORT][:IFACE]... [--username USER] [--key KEY] [-J PROXY] [-A] [--tag TAG]
  list [--raw]
  info NAME
  set NAME [--username USER] [--key KEY] [-J PROXY] [-A|--no-forward-agent]
  rename OLD NEW
  host add NAME IP[:PORT][:IFACE]...
  host remove NAME IFACE
  run NAME -- COMMAND | run --all|--tag TAG -- COMMAND
  facts NAME | facts --all|--tag TAG [--refresh]
  push SOURCE... NAME:DEST [--all] [--tag TAG] [--dry-run]
  pull NAME:SOURCE DEST [--dry-run]
  tag NAME TAG...  |  untag NAME TAG...
  ssh-config [NAME]
  check NAME [--ssh] [--timeout MS]
  check --all [--ssh] [--timeout MS]
  pick
  connect NAME [--interface IFACE] [--command COMMAND] [--dry-run]
  remove NAME

Selecting machines:
  --all                     every registered machine
  --tag TAG                 every machine carrying that tag (repeatable)

SSH options:
  -J, --proxy-jump PROXY    ssh ProxyJump host
  -A, --forward-agent       enable SSH agent forwarding
  --ssh (check)             test real SSH auth instead of TCP reachability

All ssh invocations reuse a ControlMaster socket (under the wing data dir)
so connect/check/sync share one connection per machine+interface.
"""

proc handleMachine*(argsIn: seq[string]) =
  var args = argsIn
  if args.len == 0 or popFlag(args, ["-h", "--help"]):
    showMachineHelp()
    return
  let command = args[0]
  args.delete(0)
  let path = ensureMachinesFile()
  var machines = parseMachines(path)

  case command
  of "add", "a", "new":
    let username = popValue(args, ["-u", "--username"], getEnv("USER", "root"))
    let key = popValue(args, ["-k", "--key"], getHomeDir() / ".ssh" / "id_rsa")
    let proxyJump = popValue(args, ["-J", "--proxy-jump"])
    let forwardAgent = popFlag(args, ["-A", "--forward-agent"])
    let tags = popValues(args, ["--tag", "--tags"])
    rejectUnknownOptions(args)
    requireArgs(args, 2, "wing machine add NAME IP[:PORT][:IFACE]... [options]")
    let name = args[0]
    args.delete(0)
    let hosts = args.mapIt(parseHost(it))
    var idx = -1
    for i, machine in machines:
      if machine.name == name:
        idx = i
        break
    if idx >= 0:
      for host in hosts:
        if machines[idx].hosts.anyIt(it.iface == host.iface):
          die("Error: Machine with name " & name & " and interface " &
              host.iface & " already exists")
      machines[idx].hosts.add(hosts)
      machines[idx].username = username
      machines[idx].key = key
      machines[idx].proxyJump = proxyJump
      machines[idx].forwardAgent = forwardAgent
      for tag in tags:
        if tag notin machines[idx].tags:
          machines[idx].tags.add(tag)
    else:
      machines.add(Machine(name: name, username: username, key: key,
          proxyJump: proxyJump, forwardAgent: forwardAgent, tags: tags,
          hosts: hosts))
    writeMachines(path, machines)
    echo "Machine '" & name & "' added successfully"
  of "list", "l", "ls":
    let raw = popFlag(args, ["-r", "--raw"])
    let asJson = popFlag(args, ["--json"])
    discard popFlag(args, ["-H", "--hosty"])
    rejectUnknownOptions(args)
    if asJson:
      printJsonArray(machines, machineJson)
    elif raw:
      for machine in machines:
        for host in machine.hosts:
          echo machine.name & "\t" & machine.username & "\t" & host.ip & "\t" &
              host.port & "\t" & host.iface
    else:
      # How many projects are on each machine, and what it is. Both are things you look up about a
      # machine, so they live where the machines are listed rather than in a command of their own.
      let projects = parseProjects(ensureProjectsFile())
      let known = parseFacts(factsFile())
      var rows: seq[seq[string]]
      for machine in machines:
        var count = 0
        for project in projects:
          if machineLabel(project) == machine.name:
            count.inc
        let idx = findFacts(known, machine.name)
        rows.add(@[
          machine.name,
          machine.username,
          machine.hosts.mapIt(it.ip & ":" & it.port & ":" & it.iface).join(
              ", "),
          noneIfEmpty(machine.tags.join(", ")),
          $count,
          if idx >= 0: unknownIfEmpty(known[idx].os) else: "unknown"
        ])
      # This machine holds projects too, and it is not in the registry -- leaving it out would make
      # a listing that answers "where is everything" with everything except here.
      var localCount = 0
      for project in projects:
        if project.machine.len == 0:
          localCount.inc
      if localCount > 0:
        rows.add(@["local", "-", "-", "None", $localCount, "this machine"])
      echo table(@["Name", "Username", "Addresses", "Tags", "Projects", "OS"], rows)
  of "info", "i", "show":
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing machine info NAME")
    let name = args[0]
    for machine in machines:
      if machine.name == name:
        echo "Machine: " & machine.name
        echo "Username: " & machine.username
        echo "Key: " & noneIfEmpty(machine.key)
        echo "ProxyJump: " & noneIfEmpty(machine.proxyJump)
        echo "ForwardAgent: " & (if machine.forwardAgent: "yes" else: "no")
        echo "Hosts:"
        if machine.hosts.len == 0:
          echo "  None"
        else:
          for host in machine.hosts:
            echo "  " & host.ip & ":" & host.port & " (" & host.iface & ")"
        return
    die("Machine '" & name & "' not found")
  of "set", "update", "edit":
    let username = popValue(args, ["-u", "--username"])
    let key = popValue(args, ["-k", "--key"])
    let proxyJump = popValue(args, ["-J", "--proxy-jump"])
    let forwardAgent = popFlag(args, ["-A", "--forward-agent"])
    let noForwardAgent = popFlag(args, ["--no-forward-agent"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing machine set NAME [options]")
    if username.len == 0 and key.len == 0 and proxyJump.len == 0 and
        not forwardAgent and not noForwardAgent:
      die("No machine fields were provided", 2)
    let name = args[0]
    for i in 0 .. machines.high:
      if machines[i].name == name:
        if username.len > 0:
          machines[i].username = username
        if key.len > 0:
          machines[i].key = key
        if proxyJump.len > 0:
          machines[i].proxyJump = proxyJump
        if forwardAgent:
          machines[i].forwardAgent = true
        if noForwardAgent:
          machines[i].forwardAgent = false
        writeMachines(path, machines)
        echo "Machine '" & name & "' updated successfully"
        return
    die("Machine '" & name & "' not found")
  of "rename", "mv":
    rejectUnknownOptions(args)
    requireArgs(args, 2, "wing machine rename OLD NEW")
    let oldName = args[0]
    let newName = args[1]
    if machines.anyIt(it.name == newName):
      die("Machine '" & newName & "' already exists")
    for i in 0 .. machines.high:
      if machines[i].name == oldName:
        machines[i].name = newName
        writeMachines(path, machines)
        echo "Machine '" & oldName & "' renamed to '" & newName & "'"
        return
    die("Machine '" & oldName & "' not found")
  of "host", "hosts":
    rejectUnknownOptions(args)
    requireArgs(args, 3, "wing machine host add|remove NAME HOST_OR_IFACE")
    let action = args[0]
    let name = args[1]
    var idx = -1
    for i, machine in machines:
      if machine.name == name:
        idx = i
        break
    if idx < 0:
      die("Machine '" & name & "' not found")
    case action
    of "add":
      for rawHost in args[2 .. ^1]:
        let host = parseHost(rawHost)
        if machines[idx].hosts.anyIt(it.iface == host.iface):
          die("Error: Machine with name " & name & " and interface " &
              host.iface & " already exists")
        machines[idx].hosts.add(host)
      writeMachines(path, machines)
      echo "Machine '" & name & "' hosts updated"
    of "remove", "rm":
      let iface = args[2]
      let before = machines[idx].hosts.len
      machines[idx].hosts = machines[idx].hosts.filterIt(it.iface != iface)
      if machines[idx].hosts.len == before:
        die("Host interface '" & iface & "' not found on machine '" & name & "'")
      writeMachines(path, machines)
      echo "Machine '" & name & "' hosts updated"
    else:
      die("Unknown machine host action: " & action, 2)
  of "pick", "p", "select":
    rejectUnknownOptions(args)
    for machine in machines:
      for host in machine.hosts:
        echo machine.name & "\t" & machine.username & "\t" & host.ip & "\t" &
            host.port & "\t" & host.iface
  of "connect", "c", "ssh":
    let iface = popValue(args, ["-i", "--interface"])
    let remoteCommand = popValue(args, ["-c", "--command"])
    let dryRun = popFlag(args, ["--dry-run", "--print-command"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing machine connect NAME [--interface IFACE] [--command COMMAND] [--dry-run]")
    let name = args[0]
    var machine: Machine
    var hasMachine = false
    for item in machines:
      if item.name == name:
        machine = item
        hasMachine = true
        break
    if not hasMachine:
      die("Machine '" & name & "' not found")
    var host: Host
    var hasHost = false
    for item in machine.hosts:
      if (iface.len == 0 and not hasHost) or item.iface == iface:
        host = item
        hasHost = true
        if iface.len > 0:
          break
    if not hasHost:
      die("No suitable host found for machine '" & name & "'")
    var connectArgs = sshOptionArgs(machine, host)
    connectArgs.add(machine.username & "@" & host.ip)
    if remoteCommand.len > 0:
      connectArgs.add(remoteCommand)
    if dryRun:
      echo shellDisplay("ssh", connectArgs)
      return
    echo "Connecting to " & name & " via " & host.iface & "..."
    try:
      let process = startProcess("ssh", args = connectArgs, options = {poUsePath})
      let status = process.waitForExit()
      process.close()
      if status != 0:
        quit(status)
    except CatchableError as e:
      die("Unable to start ssh: " & e.msg)
  of "run", "exec", "x":
    handleRun(args)
  of "facts", "info-remote":
    handleFacts(args)
  of "push", "upload":
    handlePush(args)
  of "pull", "download":
    handlePull(args)
  of "tag", "untag":
    let removing = command == "untag"
    rejectUnknownOptions(args)
    requireArgs(args, 2, "wing machine " & command & " NAME TAG...")
    let name = args[0]
    var found = -1
    for i, machine in machines:
      if machine.name == name:
        found = i
        break
    if found < 0:
      die("Machine '" & name & "' not found", 2)
    for tag in args[1 .. ^1]:
      let has = tag in machines[found].tags
      if removing and has:
        machines[found].tags.delete(machines[found].tags.find(tag))
      elif not removing and not has:
        machines[found].tags.add(tag)
    writeMachines(path, machines)
    echo name & ": " & (if machines[found].tags.len >
        0: machines[found].tags.join(", ") else: "no tags")
  of "ssh-config", "config":
    rejectUnknownOptions(args)
    if args.len > 1:
      die("Usage: wing machine ssh-config [NAME]", 2)
    if args.len == 0:
      for machine in machines:
        writeSshConfig(machine)
    else:
      let name = args[0]
      for machine in machines:
        if machine.name == name:
          writeSshConfig(machine)
          return
      die("Machine '" & name & "' not found")
  of "check", "health":
    let all = popFlag(args, ["--all"])
    let useSsh = popFlag(args, ["--ssh"])
    let timeoutValue = popValue(args, ["--timeout"], "1000")
    rejectUnknownOptions(args)
    var timeoutMs = 1000
    try:
      timeoutMs = parseInt(timeoutValue)
    except ValueError:
      die("Invalid timeout: " & timeoutValue, 2)
    if timeoutMs < 1:
      die("Invalid timeout: " & timeoutValue, 2)
    if not all:
      requireArgs(args, 1, "wing machine check NAME [--ssh] [--timeout MS]")
    var rows: seq[seq[string]] = @[]
    var failed = false
    for machine in machines:
      if all or machine.name == args[0]:
        for host in machine.hosts:
          var status: string
          if useSsh:
            # Real auth test (reuses the ControlMaster socket).
            let r = sshReachable(machine, host, timeoutMs)
            status = if r.ok: "auth ok" else: "auth failed"
            if not r.ok:
              failed = true
          else:
            let ok = tcpReachable(host, timeoutMs)
            status = if ok: "reachable" else: "unreachable"
            if not ok:
              failed = true
          rows.add(@[
            machine.name,
            host.iface,
            host.ip,
            host.port,
            status
          ])
    if rows.len == 0:
      if all:
        die("No machines found")
      else:
        die("Machine '" & args[0] & "' not found")
    echo table(@["Machine", "Iface", "IP", "Port", "Status"], rows)
    if failed:
      quit(1)
  of "remove", "r", "rm", "delete":
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing machine remove NAME")
    let name = args[0]
    let before = machines.len
    machines = machines.filterIt(it.name != name)
    if machines.len == before:
      die("Machine '" & name & "' not found")
    writeMachines(path, machines)
    echo "Machine '" & name & "' removed successfully"
  else:
    die("Unknown machine command: " & command, 2)
