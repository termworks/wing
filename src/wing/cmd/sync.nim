## `wing sync` — rsync-over-SSH targets between a project and a machine.

import std/[os, sequtils, strutils]

import ../cliargs
import ./sync_hosts
import ../jsonfmt
import ../rsync
import ../ssh
import ../store/machines
import ../store/projects
import ../store/syncs
import ../types
import ../util

proc resolveProjectPath*(name: string): string =
  let projects = parseProjects(ensureProjectsFile())
  for p in projects:
    if p.name == name:
      return p.path
  ""

proc resolveMachineTarget*(machine, iface: string): tuple[ok: bool; user,
    host, port, key: string] =
  let machines = parseMachines(ensureMachinesFile())
  for m in machines:
    if m.name == machine:
      var host: Host = default(Host)
      var found = false
      for h in m.hosts:
        if iface.len == 0 or h.iface == iface:
          host = h
          found = true
          break
      if not found and m.hosts.len > 0:
        host = m.hosts[0]
        found = true
      if found:
        return (true, m.username, host.ip, host.port, m.key)
  result = (false, "", "", "", "")

proc showSyncHelp*() =
  echo """
Usage: wing sync <COMMAND>

Synchronize a registered project with a directory on a remote machine over SSH.
Runs rsync over SSH, reusing the machine's ControlMaster socket (the same one
wing machine connect / check --ssh use), so one connection is shared.

Commands:
  project SOURCE DEST [--to PATH] [--delete] [--dry-run] [--register]
  add NAME --project P --machine M --remote PATH [options]
  list [--raw]
  info NAME [--json]
  run NAME [--dry-run] [--delete] [--direction push|pull]
  set NAME [options]
  rename OLD NEW
  remove NAME

add options:
  --project NAME        registered project (provides the local path)
  --machine NAME        registered machine (provides ssh target)
  --interface IFACE     which host on the machine (default: first)
  --remote PATH         remote directory
  --direction push|pull default push
  --delete              mirror: remove files on destination not at source
  --exclude PATH        repeatable; passed to rsync as --exclude

project options:
  SOURCE                registered project: NAME or HOST:NAME
  DEST                  a machine (tron), or a project on one (tron:api)
  --to PATH             destination path, when it differs from the source's
  --direct              run rsync on the source machine instead of relaying
                        here; needs the source to be able to ssh to the dest
  --register            record the copy in the registry as a project on DEST

run options:
  --dry-run             print the rsync command without transferring
  --delete              enable mirror deletes for this run
  --direction push|pull override the stored direction
"""

proc handleSync*(argsIn: seq[string]) =
  var args = argsIn
  if args.len == 0 or popFlag(args, ["-h", "--help"]):
    showSyncHelp()
    return
  let command = args[0]
  args.delete(0)
  let path = ensureSyncsFile()
  var syncs = parseSyncs(path)

  case command
  of "project", "between", "p":
    handleSyncProject(args)
  of "add", "a", "new", "create":
    let project = popValue(args, ["--project"])
    let machine = popValue(args, ["--machine"])
    let iface = popValue(args, ["--interface", "--iface"])
    let remotePath = popValue(args, ["--remote"])
    let direction = popValue(args, ["--direction"], "push")
    let doDelete = popFlag(args, ["--delete"])
    let excludes = popValues(args, ["--exclude"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing sync add NAME [options]")
    let name = args[0]
    if name.len == 0:
      die("sync target name is required", 2)
    if project.len == 0:
      die("--project is required", 2)
    if machine.len == 0:
      die("--machine is required", 2)
    if remotePath.len == 0:
      die("--remote is required", 2)
    if direction notin ["push", "pull"]:
      die("--direction must be push or pull", 2)
    if syncs.anyIt(it.name == name):
      die("Sync target '" & name & "' already exists")
    if resolveProjectPath(project).len == 0:
      die("Project '" & project & "' is not registered")
    if not resolveMachineTarget(machine, iface).ok:
      die("Machine '" & machine & "' is not registered")
    let stamp = nowStamp()
    syncs.add(SyncTarget(
      name: name,
      project: project,
      machine: machine,
      iface: iface,
      remotePath: remotePath,
      direction: direction,
      delete: doDelete,
      exclude: excludes,
      createdAt: stamp,
      updatedAt: stamp
    ))
    writeSyncs(path, syncs)
    echo "Sync target '" & name & "' added"
  of "list", "l", "ls":
    let raw = popFlag(args, ["-r", "--raw"])
    rejectUnknownOptions(args)
    if raw:
      for s in syncs:
        echo s.name & "\t" & s.project & "\t" & s.machine & "\t" &
            s.remotePath & "\t" & s.direction
    else:
      echo table(
        @["Name", "Project", "Machine", "Remote", "Direction", "Created"],
        syncs.mapIt(@[
          it.name,
          it.project,
          it.machine,
          it.remotePath,
          it.direction,
          dateOnly(it.createdAt)
        ])
      )
  of "info", "i", "show":
    let asJson = popFlag(args, ["--json"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing sync info NAME")
    let name = args[0]
    let idx = findSync(syncs, name)
    if idx < 0:
      die("Sync target '" & name & "' not found")
    let s = syncs[idx]
    if asJson:
      echo "{\"name\": " & jsonString(s.name) & ", \"project\": " &
          jsonString(s.project) & ", \"machine\": " & jsonString(s.machine) &
          ", \"interface\": " & jsonString(s.iface) & ", \"remote_path\": " &
          jsonString(s.remotePath) & ", \"direction\": " & jsonString(
          s.direction) & ", \"delete\": " & (if s.delete: "true" else:
        "false") & ", \"exclude\": " & jsonStringArray(s.exclude) &
        ", \"created_at\": " & jsonString(s.createdAt) & ", \"updated_at\": " &
        jsonString(s.updatedAt) & "}"
    else:
      echo "Sync: " & s.name
      echo "Project: " & s.project
      echo "Machine: " & s.machine
      if s.iface.len > 0:
        echo "Interface: " & s.iface
      echo "Remote: " & s.remotePath
      echo "Direction: " & s.direction
      echo "Delete: " & (if s.delete: "yes" else: "no")
      if s.exclude.len > 0:
        echo "Exclude: " & s.exclude.join(", ")
      echo "Created: " & displayStamp(s.createdAt)
      echo "Updated: " & displayStamp(s.updatedAt)
  of "run":
    let dryRun = popFlag(args, ["--dry-run"])
    let deleteOverride = popFlag(args, ["--delete"])
    let directionOverride = popValue(args, ["--direction"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing sync run NAME [--dry-run]")
    let name = args[0]
    let idx = findSync(syncs, name)
    if idx < 0:
      die("Sync target '" & name & "' not found")
    var s = syncs[idx]
    if deleteOverride:
      s.delete = true
    if directionOverride.len > 0:
      if directionOverride notin ["push", "pull"]:
        die("--direction must be push or pull", 2)
      s.direction = directionOverride
    let localRoot = resolveProjectPath(s.project)
    if localRoot.len == 0 or not dirExists(localRoot):
      die("Local project path for '" & s.project & "' is missing")
    # Resolve the full machine + host so we reuse its ssh options (ControlMaster
    # socket, ProxyJump, agent forwarding) — same connection connect/check use.
    let machines = parseMachines(ensureMachinesFile())
    var machine: Machine
    var foundM = false
    for m in machines:
      if m.name == s.machine:
        machine = m
        foundM = true
        break
    if not foundM:
      die("Machine '" & s.machine & "' is not registered")
    var host: Host
    var foundH = false
    for h in machine.hosts:
      if s.iface.len == 0 or h.iface == s.iface:
        host = h
        foundH = true
        break
    if not foundH:
      die("Machine '" & s.machine & "' has no host" &
          (if s.iface.len > 0: " on interface " & s.iface else: ""))
    let direction = s.direction
    let target = machine.username & "@" & host.ip & ":" & s.remotePath
    echo "Sync '" & s.name & "' (" & direction & ") via rsync"
    echo "  local:  " & localRoot
    echo "  remote: " & target
    if findExe("rsync").len == 0:
      die("rsync is required on PATH")
    let sshCmd = "ssh " & sshOptionArgs(machine, host).join(" ")
    # Trailing slash on the source = mirror contents into the destination.
    let src = if direction == "push": localRoot else: target
    let dst = if direction == "push": target else: localRoot
    let srcNorm = if src.endsWith("/"): src else: src & "/"
    let dstNorm = if dst.endsWith("/"): dst else: dst & "/"
    let rsyncArgs = buildRsyncCmd(srcNorm, dstNorm, sshCmd, s.delete, s.exclude,
        dryRun, compress = true)
    if dryRun:
      echo "  command: " & formatCmd(rsyncArgs)
      return
    let applied = runRsync(rsyncArgs)
    if applied.output.strip().len > 0:
      echo applied.output
    if not applied.ok:
      quit(1)
  of "set", "update", "edit":
    let remotePath = popValue(args, ["--remote"])
    let direction = popValue(args, ["--direction"])
    let doDelete = popFlag(args, ["--delete"])
    let noDelete = popFlag(args, ["--no-delete"])
    let excludes = popValues(args, ["--exclude"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing sync set NAME [options]")
    let name = args[0]
    let idx = findSync(syncs, name)
    if idx < 0:
      die("Sync target '" & name & "' not found")
    if remotePath.len == 0 and direction.len == 0 and excludes.len == 0 and
        not doDelete and not noDelete:
      die("No sync fields were provided", 2)
    if direction.len > 0 and direction notin ["push", "pull"]:
      die("--direction must be push or pull", 2)
    if remotePath.len > 0:
      syncs[idx].remotePath = remotePath
    if direction.len > 0:
      syncs[idx].direction = direction
    if doDelete:
      syncs[idx].delete = true
    if noDelete:
      syncs[idx].delete = false
    if excludes.len > 0:
      syncs[idx].exclude = excludes
    syncs[idx].updatedAt = nowStamp()
    writeSyncs(path, syncs)
    echo "Sync target '" & name & "' updated"
  of "rename", "mv":
    rejectUnknownOptions(args)
    requireArgs(args, 2, "wing sync rename OLD NEW")
    let oldName = args[0]
    let newName = args[1]
    if syncs.anyIt(it.name == newName):
      die("Sync target '" & newName & "' already exists")
    let idx = findSync(syncs, oldName)
    if idx < 0:
      die("Sync target '" & oldName & "' not found")
    syncs[idx].name = newName
    syncs[idx].updatedAt = nowStamp()
    writeSyncs(path, syncs)
    echo "Renamed '" & oldName & "' to '" & newName & "'"
  of "remove", "rm", "delete", "del":
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing sync remove NAME")
    let name = args[0]
    let before = syncs.len
    syncs = syncs.filterIt(it.name != name)
    if syncs.len == before:
      die("Sync target '" & name & "' not found")
    writeSyncs(path, syncs)
    echo "Sync target '" & name & "' removed"
  else:
    die("Unknown sync command: " & command, 2)
