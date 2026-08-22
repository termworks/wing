## Argument dispatch for the wing CLI.

import std/os

import ./cliargs
import ./help
import ./meta
import ./util

import ./cmd/completions
import ./cmd/data
import ./cmd/env
import ./cmd/init
import ./cmd/machine
import ./cmd/project
import ./cmd/sync
import "./cmd/template"

proc main*() =
  var args = commandLineParams()
  if args.len == 0:
    showHelp()
    return
  if popFlag(args, ["-h", "--help"]):
    showHelp()
    return
  if popFlag(args, ["-V", "--version"]):
    echo Version
    return
  if popFlag(args, ["--about"]):
    echo About
    return
  if args.len > 0 and args[0] == "help":
    args.delete(0)
    handleHelpCommand(args)
    return

  requireArgs(args, 1, "wing <COMMAND>")
  let command = args[0]
  args.delete(0)
  case command
  of "project", "p", "projects", "proj":
    handleProject(args)
  of "machine", "m", "machines", "host", "hosts":
    handleMachine(args)
  of "template", "t", "templates", "temp":
    handleTemplate(args)
  of "env", "e":
    handleEnv(args)
  of "sync", "s":
    handleSync(args)
  of "init", "initialize":
    handleInit(args)
  of "data", "d":
    handleData(args)
  of "completions", "completion":
    handleCompletions(args)
  else:
    die("Unknown command: " & command, 2)
