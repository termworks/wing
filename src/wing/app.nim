## Argument dispatch for the wing CLI.

import std/os

import ./cliargs
import ./help
import ./meta
import ./util

import ./cmd/shell
import ./cmd/status
import ./cmd/doctor
import ./cmd/completions
import ./cmd/data
import ./cmd/env
import ./cmd/init
import ./cmd/machine
import ./cmd/new
import ./cmd/project
import ./cmd/server
import ./cmd/agent
import ./cmd/skill
import ./cmd/sync
import "./cmd/template"
import ./cmd/todo

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
  of "new", "create":
    handleNew(args)
  of "todo", "td", "todos", "task", "tasks":
    handleTodo(args)
  of "plan", "pl", "plans":
    handlePlan(args)
  of "agent", "ag", "agents":
    handleAgent(args)
  of "skill", "sk", "skills":
    handleSkill(args)
  of "server", "login":
    if command == "login":
      args.insert("login", 0)
    handleServer(args)
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
  of "doctor", "check", "diagnose":
    handleDoctor(args)
  of "ssh", "connect", "go":
    handleSsh(args)
  of "status", "st":
    handleStatus(args)
  of "where", "path":
    handleWhere(args)
  of "data", "d":
    handleData(args)
  of "completions", "completion":
    handleCompletions(args)
  else:
    die("Unknown command: " & command, 2)
