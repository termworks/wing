## Running one command on many machines.
##
## The ssh layer already knew how to *reach* a machine; this is what finally does something once it
## is there. Everything else here -- facts, file transfer -- is this with a different command.
##
## Concurrent by default, because the alternative is not "slower", it is "unusable": a fleet of ten
## machines checked one after another takes ten round trips, and nobody runs a command that takes a
## minute to tell them something they wanted at a glance. The ControlMaster socket the ssh layer
## already opens makes the second connection to a machine nearly free.

import std/[algorithm, os, osproc, streams, strutils, times]

import ./ssh
import ./types

type
  RemoteResult* = object
    machine*: string
    host*: Host
    exitCode*: int
    output*: string
    failed*: bool ## the connection never got far enough to run anything

  RemoteTarget* = object
    machine*: Machine
    host*: Host

proc firstHost*(machine: Machine): Host =
  ## The host a command reaches this machine on. `local` first: an interface on the same network is
  ## the fast route, and it is also the one that works when the machine has no public address.
  for host in machine.hosts:
    if host.iface == "local" and host.ip.len > 0:
      return host
  for host in machine.hosts:
    if host.ip.len > 0:
      return host
  Host(ip: "", port: "22", iface: "local")

proc matchesTag*(machine: Machine; tags: seq[string]): bool =
  ## An empty selection matches nothing, not everything: `--tag` with no tags is a mistake worth
  ## noticing, and `--all` is how you say every machine.
  for tag in tags:
    if tag in machine.tags:
      return true
  false

proc selectMachines*(machines: seq[Machine]; names, tags: seq[string];
    all: bool): seq[Machine] =
  ## Which machines a command is aimed at: named, tagged, or all of them.
  for machine in machines:
    if all or machine.name in names or matchesTag(machine, tags):
      result.add(machine)

proc sshCommandArgs*(machine: Machine; host: Host; command: string): seq[string] =
  ## `ssh <options> user@host -- <command>`, with the command handed over as one word so the remote
  ## shell parses it rather than the local one taking a bite first.
  ##
  ## BatchMode is forced on, overriding the shared options: nothing here is attached to a terminal,
  ## so a machine that wants a passphrase must fail and say so. Without it ssh reaches for
  ## ssh-askpass, and a fleet-wide command becomes ten hidden password prompts.
  result = @["-o", "BatchMode=yes"] & sshOptionArgs(machine, host)
  result.add(if machine.username.len > 0: machine.username & "@" &
      host.ip else: host.ip)
  result.add("--")
  result.add(command)

proc runOn*(targets: seq[RemoteTarget]; command: string;
    timeoutMs = 0): seq[RemoteResult] =
  ## Every target at once, answers collected as they finish.
  ##
  ## The processes are started first and read afterwards, rather than started-and-read one at a
  ## time: reading a process to completion before starting the next is a sequential run wearing a
  ## loop, which is the whole thing this proc exists to avoid.
  if targets.len == 0:
    return

  var processes: seq[Process]
  for target in targets:
    if target.host.ip.len == 0:
      processes.add(nil)
      continue
    processes.add(startProcess("ssh",
        args = sshCommandArgs(target.machine, target.host, command),
        options = {poUsePath, poStdErrToStdOut}))

  let deadline = if timeoutMs > 0: epochTime() + timeoutMs.float /
      1000.0 else: 0.0
  for i, process in processes:
    if process == nil:
      result.add(RemoteResult(machine: targets[i].machine.name,
          host: targets[i].host, exitCode: -1,
          output: "no address for this machine", failed: true))
      continue

    # A machine that never answers must not hold the others hostage, so a deadline that has passed
    # kills the process rather than waiting on it. Without this one unreachable host turns a
    # fleet-wide command into a hang with no output at all.
    if deadline > 0.0:
      while process.running and epochTime() < deadline:
        sleep(50)
      if process.running:
        process.terminate()
        discard process.waitForExit()
        result.add(RemoteResult(machine: targets[i].machine.name,
            host: targets[i].host, exitCode: -1,
            output: "timed out", failed: true))
        process.close()
        continue

    let captured = process.outputStream.readAll()
    let code = process.waitForExit()
    process.close()
    result.add(RemoteResult(machine: targets[i].machine.name,
        host: targets[i].host, exitCode: code, output: captured,
        failed: code == 255))

proc targetsFor*(machines: seq[Machine]): seq[RemoteTarget] =
  for machine in machines:
    result.add(RemoteTarget(machine: machine, host: firstHost(machine)))

proc summarize*(results: seq[RemoteResult]): tuple[ok, failed: int] =
  for r in results:
    if r.exitCode == 0: result.ok.inc else: result.failed.inc

proc sortedByName*(results: seq[RemoteResult]): seq[RemoteResult] =
  ## Named order, not the order they happened to finish in: output that reorders itself between two
  ## runs of the same command cannot be diffed, and comparing two runs is most of why you ran it.
  result = results
  result.sort(proc (a, b: RemoteResult): int = cmp(a.machine, b.machine))
