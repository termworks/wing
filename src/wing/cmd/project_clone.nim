## `wing project clone` and `wing project adopt` — getting a project into the registry.
##
## Cloning already tells you everything the registry wants to know, and doing it by hand is three
## commands that each repeat part of the last one: clone somewhere, remember where, register it.
## This is those three, once, and it works the same whether the machine you want it on is this one.

import std/[os, osproc, strutils]

import ../cliargs
import ../discovery
import ../projects/layout
import ../projects/locate
import ../remote
import ../store/machines
import ../store/projects
import ../types
import ../util

proc registerProject(name, path, machine, language: string): bool =
  ## True when it was added rather than already known. The same path on the same machine is the same
  ## project, which is what makes running this twice harmless.
  let file = ensureProjectsFile()
  var projects = parseProjects(file)
  for project in projects:
    if project.path == path and project.machine == machine:
      return false
  let stamp = nowStamp()
  projects.add(Project(name: name, path: path, machine: machine,
      namespace: "default", language: language, tags: @[], createdAt: stamp,
      updatedAt: stamp))
  writeProjects(file, projects)
  true

proc detectLanguage(path: string): string =
  let detected = detectProject(path)
  if detected.found: detected.project.language else: ""

proc handleClone*(argsIn: seq[string]) =
  var args = argsIn
  let onMachine = popValue(args, ["-m", "--machine"])
  let intoRoot = popValue(args, ["--root"], codeRoot())
  let atPath = popValue(args, ["--path"])
  let branch = popValue(args, ["-b", "--branch"])
  let dryRun = popFlag(args, ["--dry-run", "-n"])
  rejectUnknownOptions(args)
  requireArgs(args, 1,
      "wing project clone URL|owner/name [--machine NAME] [--root DIR] [--branch B]")

  let repo = parseRepoRef(args[0])
  if repo.name.len == 0:
    die("Could not read a repository out of '" & args[0] & "'", 2)
  let target = if atPath.len > 0: atPath else: layoutPath(intoRoot, repo)

  var command = "git clone"
  if branch.len > 0:
    command.add(" --branch " & quoteShell(branch))
  command.add(" " & quoteShell(repo.url) & " " & quoteShell(target))

  if dryRun:
    echo (if onMachine.len > 0: onMachine & ": " else: "") & command
    return

  if onMachine.len > 0:
    let machines = parseMachines(ensureMachinesFile())
    var found = false
    var machine: Machine
    for candidate in machines:
      if candidate.name == onMachine:
        machine = candidate
        found = true
        break
    if not found:
      die("Machine '" & onMachine & "' not found", 2)
    # mkdir first: git will not create the parents, and the layout is several levels deep.
    let script = "mkdir -p " & quoteShell(parentDir(target)) & " && " & command
    let results = runOn(@[RemoteTarget(machine: machine, host: firstHost(
        machine))], script, 0)
    for r in results:
      for line in r.output.strip().splitLines():
        if line.strip().len > 0:
          echo "  " & line
      if r.exitCode != 0:
        die("clone failed on " & onMachine, 1)
    # The language is read on the machine that has the files, since this one does not.
    let asked = runOn(@[RemoteTarget(machine: machine, host: firstHost(
        machine))], "cd " & quoteShell(target) & " && ls", 0)
    var language = ""
    if asked.len > 0 and asked[0].exitCode == 0:
      for line in asked[0].output.splitLines():
        case line.strip()
        of "Cargo.toml": language = "rust"
        of "go.mod": language = "go"
        of "pyproject.toml": language = "python"
        of "package.json": language = "node"
        of "build.zig": language = "zig"
        of "dub.json": language = "d"
        else:
          if line.strip().endsWith(".nimble"): language = "nim"
    discard registerProject(repo.name, target, onMachine, language)
    echo repo.name & " -> " & onMachine & ":" & target
    return

  createDir(parentDir(target))
  if execCmd(command) != 0:
    die("clone failed", 1)
  discard registerProject(repo.name, target, "", detectLanguage(target))
  echo repo.name & " -> " & target

proc handleAdopt*(argsIn: seq[string]) =
  ## An existing checkout, moved into the layout and registered. `--in-place` keeps it where it is
  ## and only registers, which is what you want for a directory that other things point at.
  var args = argsIn
  let inPlace = popFlag(args, ["--in-place", "--here"])
  let intoRoot = popValue(args, ["--root"], codeRoot())
  let dryRun = popFlag(args, ["--dry-run", "-n"])
  rejectUnknownOptions(args)
  let source = expandFilename(if args.len > 0: args[0] else: getCurrentDir())
  if not dirExists(source):
    die("'" & source & "' is not a directory", 2)

  if inPlace:
    let name = source.lastPathPart
    if dryRun:
      echo "register " & name & " -> " & source
      return
    if registerProject(name, source, "", detectLanguage(source)):
      echo "registered " & name & " -> " & source
    else:
      echo name & " was already registered"
    return

  # Where it belongs is read from the remote it was cloned from, which is the only thing that knows.
  # The exit code decides, not the output: execCmdEx merges stderr, so a directory that is not a
  # repository answers with git's error text -- which has slashes and a colon in it and parses as a
  # URL if you only check that something came back.
  let asked = execCmdEx("git -C " & quoteShell(source) & " remote get-url origin")
  let remote = if asked.exitCode == 0: asked.output.strip() else: ""
  if remote.len == 0:
    die("'" & source & "' has no origin remote, so there is no layout to move it into — " &
        "--in-place registers it where it is", 2)
  let repo = parseRepoRef(remote)
  if repo.name.len == 0:
    die("Could not read a repository out of '" & remote & "'", 2)
  let target = layoutPath(intoRoot, repo)
  if target == source:
    if registerProject(repo.name, source, "", detectLanguage(source)):
      echo "registered " & repo.name & " -> " & source
    else:
      echo repo.name & " is already where it belongs"
    return
  if dirExists(target):
    die("'" & target & "' already exists", 2)

  if dryRun:
    echo source & " -> " & target
    return
  createDir(parentDir(target))
  moveDir(source, target)
  discard registerProject(repo.name, target, "", detectLanguage(target))
  echo repo.name & ": " & source & " -> " & target
