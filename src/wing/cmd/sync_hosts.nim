## `wing sync project SOURCE DEST` — moving a project between machines.
##
## The rest of `wing sync` is a registry of named targets you set up once and run again. This is the
## other half: an ad-hoc copy between two hosts, named the way everything else names projects. It
## exists because once the registry knows which machine a project is on, "put this one over there"
## is a question wing can already answer the hard parts of -- which machine, which path, which key.

import std/[os, strutils]

import ../cliargs
import ../projects/locate
import ../projects/remote_discovery
import ../remote
import ../rsync
import ../ssh
import ../store/machines
import ../store/projects
import ../types
import ../util

type
  Endpoint = object
    machine: Machine ## unset when the endpoint is this machine
    host: Host
    remote: bool
    path: string
    label: string

proc machineNamed(machines: seq[Machine]; name: string): Machine =
  for machine in machines:
    if machine.name == name:
      return machine
  die("Machine '" & name & "' not found", 2)

proc sshFor(endpoint: Endpoint): string =
  ## rsync's `--rsh`, built from the same options every other ssh in wing uses, so a transfer shares
  ## the ControlMaster socket instead of opening a second connection.
  "ssh " & sshOptionArgs(endpoint.machine, endpoint.host).join(" ")

proc rsyncPath(endpoint: Endpoint; trailing: bool): string =
  var path = endpoint.path
  if trailing and not path.endsWith("/"):
    path.add("/")
  if not endpoint.remote:
    return path
  let user = if endpoint.machine.username.len > 0: endpoint.machine.username & "@" else: ""
  user & endpoint.host.ip & ":" & path

proc sourceEndpoint(projects: seq[Project]; machines: seq[Machine];
    reference: string): tuple[endpoint: Endpoint; project: Project] =
  let matches = locate(projects, reference)
  if matches.len == 0:
    die("No project called '" & reference & "'", 2)
  if matches.len > 1:
    die(describeAmbiguity(matches), 2)
  let project = matches[0].project
  var endpoint = Endpoint(path: project.path, label: qualifiedName(project))
  if isRemote(project):
    endpoint.machine = machineNamed(machines, project.machine)
    endpoint.host = firstHost(endpoint.machine)
    endpoint.remote = true
    if endpoint.host.ip.len == 0:
      die("Machine '" & project.machine & "' has no address", 2)
  (endpoint, project)

proc destinationEndpoint(projects: seq[Project]; machines: seq[Machine];
    reference, override: string; source: Project): Endpoint =
  ## The destination may name a machine (`tron`), or a project on one (`tron:api`). A machine on its
  ## own means "the same project, over there", which is the common case and the reason a second
  ## registry entry is not required before the first copy.
  let (machineName, name) = splitQualified(reference)
  let host = if machineName.len > 0: machineName else: reference
  let projectName = if machineName.len > 0: name else: source.name

  var path = override
  if path.len == 0:
    for project in projects:
      if project.name == projectName and machineLabel(project) == host:
        path = project.path
        break
  if path.len == 0:
    # Nothing registered over there yet, so the source's own path is the best guess -- and the one
    # that keeps a project at the same place on every machine, which is what people expect.
    path = source.path

  result = Endpoint(path: path, label: host & ":" & projectName)
  if host == "local":
    return
  result.machine = machineNamed(machines, host)
  result.host = firstHost(result.machine)
  result.remote = true
  if result.host.ip.len == 0:
    die("Machine '" & host & "' has no address", 2)

proc report(argv: seq[string]; dryRun: bool): bool =
  ## A dry run prints the command and stops, which is what `wing sync run --dry-run` does and what
  ## makes a plan readable before a machine is touched -- rsync's own --dry-run would still have to
  ## connect to both ends to tell you anything.
  if dryRun:
    echo "  " & formatCmd(argv)
    return true
  let outcome = runRsync(argv)
  for line in outcome.output.strip().splitLines():
    if line.strip().len > 0:
      echo "  " & line
  outcome.ok

proc relay(source, destination: Endpoint; excludes: seq[string];
    doDelete, dryRun: bool): bool =
  ## Neither end is this machine, so the bytes come here and go back out.
  ##
  ## Twice the transfer, and still the right default: rsync cannot talk between two remote hosts on
  ## its own, and the alternative -- running rsync *on* the source -- needs the source to be able to
  ## ssh to the destination, which is a thing that is usually not set up and fails confusingly when
  ## it is not. `--direct` is for when it is.
  let staging = getTempDir() / "wing-relay-" & $getCurrentProcessId()
  removeDir(staging)
  createDir(staging)
  defer: removeDir(staging)

  echo paint("via this machine", "33") & "  " & source.label & " -> here -> " &
      destination.label
  let down = buildRsyncCmd(rsyncPath(source, true), staging & "/",
      sshFor(source), false, excludes, dryRun, true)
  if not report(down, dryRun):
    return false
  # `--delete` belongs on the second leg only: applied to the staging directory it would mean
  # nothing, and applied to the destination it means what was asked for.
  let up = buildRsyncCmd(staging & "/", rsyncPath(destination, true),
      sshFor(destination), doDelete, excludes, dryRun, true)
  report(up, dryRun)

proc direct(source, destination: Endpoint; excludes: seq[string];
    doDelete, dryRun: bool): bool =
  ## rsync run on the source machine, targeting the destination. Needs the source to reach the
  ## destination itself -- wing's keys are on this machine, not on that one.
  var argv = @["rsync", "--archive", "--verbose", "--human-readable", "--compress"]
  if doDelete:
    argv.add("--delete")
  for exclude in excludes:
    if exclude.len > 0:
      argv.add("--exclude=" & exclude)
  if dryRun:
    argv.add("--dry-run")
  let user = if destination.machine.username.len > 0:
      destination.machine.username & "@" else: ""
  # The source is a plain path here, not a `user@host:` one: rsync is running *on* the source
  # machine, so that side is local to it. Handing it the remote form makes rsync see two remote
  # ends and refuse -- "the source and destination cannot both be remote".
  var sourcePath = source.path
  if not sourcePath.endsWith("/"):
    sourcePath.add("/")
  argv.add(sourcePath)
  argv.add(user & destination.host.ip & ":" & destination.path)

  echo paint("direct", "33") & "  " & source.label & " -> " &
      destination.label & "  (run on " & source.machine.name & ")"
  if dryRun:
    echo "  " & argv.join(" ")
    return true
  let results = runOn(@[RemoteTarget(machine: source.machine,
      host: source.host)], argv.join(" "), 0)
  for r in results:
    for line in r.output.strip().splitLines():
      if line.strip().len > 0:
        echo "  " & line
    if r.exitCode != 0:
      return false
  true

proc registerDestination(destination: Endpoint; source: Project) =
  ## The copy landed, so the registry should know it is there. This is the whole point of hosts
  ## being part of a project's identity: a project that exists on two machines shows up twice.
  let (host, name) = splitQualified(destination.label)
  let path = ensureProjectsFile()
  var projects = parseProjects(path)
  let stamp = nowStamp()
  var found = Project(
    name: name,
    path: destination.path,
    machine: if host == "local": "" else: host,
    namespace: if source.namespace.len > 0: source.namespace else: "default",
    templateName: source.templateName,
    description: source.description,
    language: source.language,
    framework: source.framework,
    tags: source.tags,
    createdAt: stamp,
    updatedAt: stamp
  )
  let counts = mergeDiscovered(projects, @[found], stamp)
  writeProjects(path, projects)
  if counts.added > 0:
    echo "registered " & destination.label & " -> " & destination.path

proc handleSyncProject*(argsIn: seq[string]) =
  var args = argsIn
  let dryRun = popFlag(args, ["--dry-run", "-n"])
  let doDelete = popFlag(args, ["--delete", "--mirror"])
  let useDirect = popFlag(args, ["--direct"])
  let register = popFlag(args, ["--register"])
  let override = popValue(args, ["--to", "--remote"])
  let excludes = popValues(args, ["--exclude"])
  rejectUnknownOptions(args)
  requireArgs(args, 2,
      "wing sync project SOURCE DEST [--to PATH] [--delete] [--dry-run]")

  let projects = parseProjects(ensureProjectsFile())
  let machines = parseMachines(ensureMachinesFile())
  let (source, project) = sourceEndpoint(projects, machines, args[0])
  let destination = destinationEndpoint(projects, machines, args[1], override, project)

  if source.remote and destination.remote and
      source.machine.name == destination.machine.name and
      source.path == destination.path:
    die("Source and destination are the same place", 2)

  var ok: bool
  if source.remote and destination.remote:
    ok = if useDirect: direct(source, destination, excludes, doDelete, dryRun)
         else: relay(source, destination, excludes, doDelete, dryRun)
  else:
    # One end is here, which is the case rsync handles by itself: the ssh options come from
    # whichever end is the remote one.
    let transport = if source.remote: sshFor(source) else:
        (if destination.remote: sshFor(destination) else: "")
    echo paint(source.label, "36") & " -> " & paint(destination.label, "36")
    ok = report(buildRsyncCmd(rsyncPath(source, true),
        rsyncPath(destination, true), transport, doDelete, excludes, dryRun,
        true), dryRun)

  if not ok:
    die("sync failed", 1)
  if register and not dryRun:
    registerDestination(destination, project)
