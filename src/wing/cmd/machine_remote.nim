## `wing machine run / facts / push / pull` — the subcommands that reach the machines.
##
## Separate from `machine.nim`, which is the registry: that file answers "what machines are there",
## this one answers "what are they doing". They share the store and nothing else.

import std/[os, strutils, sequtils]

import ../cliargs
import ../machines/facts
import ../remote
import ../rsync
import ../ssh
import ../store/machines
import ../types
import ../util

proc selection(args: var seq[string]; usage: string): seq[Machine] =
  ## The machines a command is aimed at: named on the command line, carrying a `--tag`, or `--all`.
  let all = popFlag(args, ["--all"])
  let tags = popValues(args, ["--tag", "--tags"])
  let machines = parseMachines(ensureMachinesFile())
  var names: seq[string]
  if not all and tags.len == 0:
    requireArgs(args, 1, usage)
    names.add(args[0])
    args.delete(0)
  result = selectMachines(machines, names, tags, all)
  if result.len == 0:
    if names.len > 0:
      die("Machine '" & names[0] & "' not found", 2)
    if tags.len > 0:
      die("No machine carries " & (if tags.len ==
          1: "the tag '" & tags[0] & "'" else: "any of those tags"), 2)
    die("No machines are registered. Add one with: wing machine add", 2)

proc reportResults(results: seq[RemoteResult]; quiet: bool): int =
  ## What each machine said, then a count. The output is grouped under the machine that produced it
  ## because interleaved lines from ten machines are one machine's output ten times over, and no
  ## line says which is which.
  let ordered = sortedByName(results)
  for r in ordered:
    let body = r.output.strip()
    if not quiet:
      let mark =
        if r.exitCode == 0: paint("✓", "32")
        else: paint("✗ exit " & $r.exitCode, "33")
      echo paint(r.machine, "36") & "  " & mark
    if body.len > 0:
      for line in body.splitLines():
        echo (if quiet: line else: "  " & line)
  let counts = summarize(ordered)
  if not quiet and ordered.len > 1:
    echo ""
    echo $counts.ok & " ok, " & $counts.failed & " failed"
  if counts.failed > 0: 1 else: 0

proc handleRun*(argsIn: seq[string]) =
  ## `wing machine run NAME -- uptime`, or `--all` / `--tag gpu` to ask the whole fleet at once.
  var args = argsIn
  let quiet = popFlag(args, ["-q", "--quiet"])
  let timeoutValue = popValue(args, ["--timeout"], "0")
  var timeoutMs = 0
  try:
    timeoutMs = parseInt(timeoutValue)
  except ValueError:
    die("Invalid timeout: " & timeoutValue, 2)

  # Everything after `--` is the remote command, kept whole. Splitting it here and rejoining it
  # there is where quoting goes to die, so it is passed across as one word.
  var command = ""
  let separator = args.find("--")
  if separator >= 0:
    command = args[separator + 1 .. ^1].join(" ")
    args = args[0 ..< separator]
  let usage = "wing machine run NAME [--all] [--tag TAG] -- COMMAND"
  let targets = selection(args, usage)
  rejectUnknownOptions(args)
  if command.strip().len == 0:
    die(usage, 2)

  let results = runOn(targetsFor(targets), command, timeoutMs)
  quit(reportResults(results, quiet))

proc handleFacts*(argsIn: seq[string]) =
  ## What each machine *is*: os, kernel, arch, cpus, memory, disk, uptime -- collected in one round
  ## trip and kept, so `wing machine list` can show it without asking again.
  var args = argsIn
  let asJson = popFlag(args, ["--json"])
  let refresh = popFlag(args, ["--refresh", "--update"])
  let raw = popFlag(args, ["-r", "--raw"])
  let usage = "wing machine facts NAME [--all] [--tag TAG] [--refresh]"
  let targets = selection(args, usage)
  rejectUnknownOptions(args)

  var known = parseFacts(factsFile())
  if refresh or known.len == 0 or targets.anyIt(findFacts(known, it.name) < 0):
    let results = runOn(targetsFor(targets), factsProbe, 20_000)
    for r in results:
      if r.exitCode != 0:
        stderr.writeLine("wing: " & r.machine & ": " & r.output.strip())
        continue
      let parsed = parseProbeOutput(r.machine, r.output)
      let idx = findFacts(known, r.machine)
      if idx >= 0: known[idx] = parsed else: known.add(parsed)
    writeFacts(factsFile(), known)

  var shown: seq[MachineFacts]
  for machine in targets:
    let idx = findFacts(known, machine.name)
    if idx >= 0:
      shown.add(known[idx])
  printFacts(shown, raw, asJson)

proc transfer(argsIn: seq[string]; push: bool) =
  ## `push` and `pull` are the same rsync with the two paths the other way round, so they are one
  ## proc: two copies would drift in exactly the option that matters.
  var args = argsIn
  let dryRun = popFlag(args, ["--dry-run", "-n"])
  let usage =
    if push: "wing machine push SOURCE... NAME:DEST [--all] [--tag TAG]"
    else: "wing machine pull NAME:SOURCE DEST"
  requireArgs(args, 2, usage)

  # The remote side is the one carrying a colon, which is also how scp and rsync read a path -- so
  # the argument order is the one people already have in their fingers.
  let remoteArg = if push: args[^1] else: args[0]
  let colon = remoteArg.find(':')
  if colon <= 0:
    die("Name the machine and the path as NAME:/path", 2)
  let machineName = remoteArg[0 ..< colon]
  let remotePath = remoteArg[colon + 1 .. ^1]
  let localPaths = if push: args[0 ..< args.high] else: @[args[1]]

  var names = @[machineName]
  var chosen = selectMachines(parseMachines(ensureMachinesFile()), names, @[], false)
  if chosen.len == 0:
    die("Machine '" & machineName & "' not found", 2)
  if not push and chosen.len > 1:
    die("Pull takes one machine: two would write to the same place", 2)

  var failed = 0
  for machine in chosen:
    let host = firstHost(machine)
    if host.ip.len == 0:
      stderr.writeLine("wing: " & machine.name & " has no address")
      failed.inc
      continue
    let user = if machine.username.len > 0: machine.username & "@" else: ""
    let remote = user & host.ip & ":" & remotePath
    # rsync is told how to reach the machine with the same ssh options everything else uses, so the
    # ControlMaster socket is shared and a transfer does not open a second connection.
    let sshCommand = "ssh " & sshOptionArgs(machine, host).join(" ")
    var argv = @["-az", "--info=stats1", "-e", sshCommand]
    if dryRun:
      argv.add("--dry-run")
    if push:
      argv.add(localPaths)
      argv.add(remote)
    else:
      argv.add(remote)
      argv.add(localPaths[0])
    echo paint(machine.name, "36") & "  " &
        (if push: localPaths.join(" ") & " -> " & remotePath
          else: remotePath & " -> " & localPaths[0])
    let moved = runRsync(@["rsync"] & argv)
    if moved.output.strip().len > 0:
      for line in moved.output.strip().splitLines():
        echo "  " & line
    if not moved.ok:
      failed.inc
  quit(if failed > 0: 1 else: 0)

proc handlePush*(args: seq[string]) = transfer(args, true)
proc handlePull*(args: seq[string]) = transfer(args, false)
