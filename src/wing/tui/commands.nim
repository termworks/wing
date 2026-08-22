## Runs wing subcommands for the info, delete, and command-prompt actions.

import std/[cmdline, os, osproc, streams, strutils]

import ../types
import ./model

proc runCliCommand*(commandInput: string): CommandResult =
  var command = commandInput.strip()
  if command.startsWith("wing "):
    command = command[3 .. ^1].strip()
  if command.len == 0:
    return CommandResult(code: 1, output: "Empty command")

  var args: seq[string]
  try:
    args = parseCmdLine(command)
  except ValueError as e:
    return CommandResult(code: 1, output: e.msg)

  if args.len == 0:
    return CommandResult(code: 1, output: "Empty command")
  if args[0] in ["tui", "ui", "dashboard"]:
    return CommandResult(code: 1, output: "Nested TUI commands are disabled inside the TUI")
  if args.len >= 2 and args[0] in ["machine", "m", "machines", "host",
      "hosts"] and args[1] in ["connect", "c", "ssh"]:
    return CommandResult(code: 1, output: "Interactive ssh is disabled inside the TUI; run this from the normal CLI")

  try:
    let process = startProcess(getAppFilename(), args = args,
        options = {poStdErrToStdOut})
    let output = process.outputStream.readAll()
    let code = process.waitForExit()
    process.close()
    result = CommandResult(code: code, output: output)
  except OSError as e:
    result = CommandResult(code: 1, output: e.msg)

proc infoCommand*(section: DashboardSection; row: seq[string]): string =
  if row.len == 0:
    return ""
  case section.title
  of "Projects":
    let namespace = if row.len > 1: row[1] else: "default"
    "project --namespace " & quoteShell(namespace) & " info " & quoteShell(row[0])
  of "Machines":
    "machine info " & quoteShell(row[0])
  of "Templates":
    "template info " & quoteShell(row[0])
  of "Sync":
    "sync info " & quoteShell(row[0])
  else:
    ""

proc deleteCommand*(section: DashboardSection; row: seq[string]): string =
  if row.len == 0:
    return ""
  case section.title
  of "Projects":
    let namespace = if row.len > 1: row[1] else: "default"
    "project --namespace " & quoteShell(namespace) & " remove " & quoteShell(row[0])
  of "Machines":
    "machine remove " & quoteShell(row[0])
  of "Templates":
    "template remove " & quoteShell(row[0])
  of "Sync":
    "sync remove " & quoteShell(row[0])
  else:
    ""
