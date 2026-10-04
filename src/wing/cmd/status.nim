## `wing status` — what is uncommitted, unpushed or stashed, across every project on every machine.
##
## The question a registry of projects on several machines should be able to answer and could not:
## where did I leave things. One probe per machine rather than one per project, because ten projects
## on one machine is one ssh connection's worth of work, not ten.

import std/[os, osproc, sequtils, strutils]

import ../cliargs
import ../projects/locate
import ../remote
import ../store/machines
import ../store/projects
import ../types
import ../util

type
  RepoState = object
    path: string
    dirty: int
    ahead: string
    branch: string
    stashes: int
    missing: bool
    notRepo: bool

const statusProbe = """
for dir in %PATHS%; do
  if [ ! -d "$dir" ]; then printf '%s\t?\t\t\t\n' "$dir"; continue; fi
  cd "$dir" 2>/dev/null || continue
  if [ ! -e .git ]; then printf '%s\t-\t\t\t\n' "$dir"; continue; fi
  dirty=$(git status --porcelain 2>/dev/null | wc -l)
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  ahead=$(git rev-list --count --left-right @{upstream}...HEAD 2>/dev/null | tr '\t' '/')
  stash=$(git stash list 2>/dev/null | wc -l)
  printf '%s\t%s\t%s\t%s\t%s\n' "$dir" "$dirty" "$branch" "$ahead" "$stash"
done
"""
  ## One shell loop over every path on that machine, so a fleet costs one connection each. Each
  ## field falls back to empty rather than failing, so a directory that is not a repository -- or
  ## not there any more -- still gets a row saying so.

proc probeFor(paths: seq[string]): string =
  var quoted: seq[string]
  for path in paths:
    quoted.add(quoteShell(path))
  statusProbe.replace("%PATHS%", quoted.join(" "))

proc parseStates(output: string): seq[RepoState] =
  for line in output.splitLines():
    if line.strip().len == 0:
      continue
    let parts = line.split('\t')
    if parts.len < 5:
      continue
    var state = RepoState(path: parts[0], branch: parts[2], ahead: parts[3])
    if parts[1] == "?":
      state.missing = true
    elif parts[1] == "-":
      state.notRepo = true
    else:
      state.dirty = try: parseInt(parts[1]) except ValueError: 0
      state.stashes = try: parseInt(parts[4].strip()) except ValueError: 0
    result.add(state)

proc describe(state: RepoState; verbose: bool): string =
  ## Empty when there is nothing to say, which is what lets the quiet default work.
  if state.missing:
    return paint("gone", "31")
  # Not a repository is not the same as nothing to report: it means nothing here is tracked at all.
  if state.notRepo:
    return paint("not a repo", "35")
  var notes: seq[string]
  if state.dirty > 0:
    notes.add(paint($state.dirty & " dirty", "33"))
  # `git rev-list --left-right` counts behind/ahead; both are worth knowing and neither is an error.
  if state.ahead.len > 0 and state.ahead != "0/0":
    let sides = state.ahead.split('/')
    if sides.len == 2:
      if sides[1] != "0":
        notes.add(paint(sides[1] & " unpushed", "36"))
      if sides[0] != "0":
        notes.add(paint(sides[0] & " behind", "35"))
  elif verbose and state.ahead.len == 0 and not state.missing and
      state.branch.len > 0:
    # Only when asked: wing generates projects with a repository and no remote, so this would be
    # true of every new project forever and would drown the things that do need attention.
    notes.add(paint("no upstream", "35"))
  if state.stashes > 0:
    notes.add($state.stashes & " stashed")
  notes.join("  ")

proc handleStatus*(argsIn: seq[string]) =
  var args = argsIn
  let all = popFlag(args, ["-a", "--all"])
  let onMachine = popValue(args, ["-m", "--machine"])
  let localOnly = popFlag(args, ["--local"])
  let timeoutValue = popValue(args, ["--timeout"], "60000")
  rejectUnknownOptions(args)
  var timeoutMs = 60_000
  try:
    timeoutMs = parseInt(timeoutValue)
  except ValueError:
    die("Invalid timeout: " & timeoutValue, 2)

  var projects = parseProjects(ensureProjectsFile())
  if onMachine.len > 0:
    projects = projects.filterIt(machineLabel(it) == onMachine)
  elif localOnly:
    projects = projects.filterIt(it.machine.len == 0)
  if projects.len == 0:
    echo "No projects to look at. Register some with: wing project discover PATH --register"
    return

  let machines = parseMachines(ensureMachinesFile())
  var anything = false

  for group in byMachine(projects):
    var paths: seq[string]
    for project in group.items:
      paths.add(project.path)

    var output = ""
    if group.machine == "local":
      # Run here rather than over ssh to this machine: the connection would be a round trip to say
      # something the filesystem under this process already knows.
      let (captured, code) = execCmdEx("sh -c " & quoteShell(probeFor(paths)))
      if code != 0 and captured.strip().len == 0:
        stderr.writeLine("wing: could not read local projects")
        continue
      output = captured
    else:
      var found = false
      var machine: Machine
      for candidate in machines:
        if candidate.name == group.machine:
          machine = candidate
          found = true
          break
      if not found:
        stderr.writeLine("wing: " & group.machine & " is not a registered machine")
        continue
      let results = runOn(@[RemoteTarget(machine: machine,
          host: firstHost(machine))], probeFor(paths), timeoutMs)
      if results.len == 0 or results[0].exitCode != 0:
        stderr.writeLine("wing: " & group.machine & ": " &
            (if results.len > 0: results[0].output.strip().splitLines()[
                ^1] else: "no answer"))
        continue
      output = results[0].output

    let states = parseStates(output)
    var shown: seq[string]
    for i, state in states:
      let note = describe(state, all)
      if note.len == 0 and not all:
        continue
      let name = if i < group.items.len: group.items[
          i].name else: state.path.lastPathPart
      shown.add("  " & name & repeat(" ", max(1, 18 - name.len)) &
          (if note.len > 0: note else: paint("clean", "32")) &
          (if state.branch.len > 0 and state.branch != "HEAD": paint(
              "   " & state.branch, "37") else: ""))
    if shown.len == 0:
      continue
    anything = true
    echo paint(group.machine, "36")
    for line in shown:
      echo line

  if not anything:
    echo paint("Everything is clean, pushed and unstashed.", "32")
