## rsync.nim — rsync-backed project sync.
##
## Sync runs `rsync` over an SSH transport. The SSH options (key, port,
## ControlMaster socket, proxy jump, agent forwarding) are assembled by the
## caller in cmd/sync.nim and passed in as `sshCmd`, which becomes rsync's
## `--rsh` value. This module owns rsync command construction and execution and
## stays free of wing's domain types.
##
## Trailing-slash semantics: the caller forms `src` and `dst` so that source
## contents mirror into the destination (the conventional project-sync behavior).

import std/[os, osproc, streams, strutils]

proc buildRsyncCmd*(src, dst, sshCmd: string; doDelete: bool;
    excludes: seq[string]; dryRun, compress: bool): seq[string] =
  ## Build a structured rsync argv. No shell, no quoting surprises.
  result = @["rsync", "--archive", "--verbose", "--human-readable"]
  if compress:
    result.add("--compress")
  if doDelete:
    result.add("--delete")
  for ex in excludes:
    if ex.len > 0:
      result.add("--exclude=" & ex)
  if dryRun:
    result.add("--dry-run")
  if sshCmd.len > 0:
    result.add(@["--rsh", sshCmd])
  result.add(src)
  result.add(dst)

proc runRsync*(args: seq[string]): tuple[ok: bool; output: string] =
  ## Execute a structured rsync argv. Returns merged stdout+stderr and success.
  if args.len == 0:
    return (false, "empty rsync command")
  try:
    let p = startProcess(args[0], args = args[1 .. ^1],
        options = {poUsePath, poStdErrToStdOut})
    result.output = p.outputStream.readAll()
    result.ok = p.waitForExit() == 0
    p.close()
  except CatchableError as e:
    result.ok = false
    result.output = "rsync failed to start: " & e.msg

proc formatCmd*(args: seq[string]): string =
  ## Render an argv as a shell-quoted command line (for --dry-run display).
  if args.len == 0:
    return ""
  result = args[0]
  for i in 1 ..< args.len:
    let a = args[i]
    if a.startsWith("--") and "=" in a:
      result.add(" " & a)
    else:
      result.add(" " & quoteShell(a))
