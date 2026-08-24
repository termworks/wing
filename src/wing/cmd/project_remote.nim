## `wing project discover --machine` — filling the registry from machines that are not this one.
##
## Separate from `project.nim` so the registry commands stay about the registry: this file is the
## only one that knows a project can be somewhere else, and it reaches the machines to find out.

import std/[strutils]

import ../discovery
import ../projects/locate
import ../projects/remote_discovery
import ../remote
import ../store/machines
import ../store/projects
import ../types
import ../util

proc registerFound(found: seq[Project]; label: string) =
  ## Merged into the registry rather than replacing it: discovery is something you re-run, and a
  ## run that forgot everything it did not see this time would delete a machine's projects the
  ## first time it was switched off.
  if found.len == 0:
    echo label & ": nothing found"
    return
  let path = ensureProjectsFile()
  var projects = parseProjects(path)
  let stamp = nowStamp()
  let counts = mergeDiscovered(projects, found, stamp)
  writeProjects(path, projects)
  echo label & ": " & $counts.added & " added, " & $counts.updated & " already known"

proc registerLocalDiscovered*(root: string; depth: int) =
  ## The same registration for this machine, so `--register` means the same thing either way.
  var found: seq[Project]
  let stamp = nowStamp()
  for detected in discoverProjects(root, depth):
    found.add(Project(
      name: detected.name,
      path: detected.path,
      machine: "",
      namespace: "default",
      language: detected.language,
      tags: @[],
      createdAt: stamp,
      updatedAt: stamp
    ))
  registerFound(found, "local")

proc discoverOnMachines*(root: string; depth: int; machineName: string;
    tags: seq[string]; onAll, register: bool) =
  ## One `find` per machine, run over ssh, all of them at once.
  let machines = parseMachines(ensureMachinesFile())
  var names: seq[string]
  if machineName.len > 0:
    names.add(machineName)
  let chosen = selectMachines(machines, names, tags, onAll)
  if chosen.len == 0:
    if machineName.len > 0:
      die("Machine '" & machineName & "' not found", 2)
    die("No machine matched", 2)

  # A remote walk of a deep tree is slow enough that a machine which has gone away must not hold
  # the others: two minutes is generous for a find and short enough to notice.
  let results = runOn(targetsFor(chosen), probeFor(root, depth), 120_000)
  let stamp = nowStamp()
  for r in sortedByName(results):
    if r.exitCode != 0:
      stderr.writeLine("wing: " & r.machine & ": " &
          r.output.strip().splitLines()[^1])
      continue
    let found = parseDiscovery(r.machine, r.output, stamp)
    if register:
      registerFound(found, r.machine)
    else:
      # Shown rather than kept, so a scan can be looked at before it becomes registry entries.
      echo paint(r.machine, "36") & "  " & $found.len & " project(s) under " & root
      for project in found:
        echo "  " & project.path &
            (if project.language.len > 0: "  (" & project.language & ")" else: "")
  if not register:
    echo ""
    echo "--register to add these to the registry"

proc handleHosts*(argsIn: seq[string]) =
  ## `wing hosts` — which machines have projects on them, and how many.
  ##
  ## The question this whole feature exists to answer: from a laptop that talks to five servers,
  ## "where is everything" should be one line each rather than five ssh sessions.
  var args = argsIn
  let raw = args.len > 0 and args[0] in ["-r", "--raw"]
  let projects = parseProjects(ensureProjectsFile())
  let machines = parseMachines(ensureMachinesFile())
  let grouped = byHost(projects)

  var rows: seq[seq[string]]
  for group in grouped:
    var languages: seq[string]
    for project in group.items:
      if project.language.len > 0 and project.language notin languages:
        languages.add(project.language)
    rows.add(@[group.host, $group.items.len, languages.join(", ")])

  # A registered machine with nothing on it is still worth a row: "no projects here" and "no such
  # machine" are different answers, and only one of them means you forgot to run discovery.
  for machine in machines:
    var seen = false
    for group in grouped:
      if group.host == machine.name:
        seen = true
        break
    if not seen:
      rows.add(@[machine.name, "0", ""])

  if raw:
    for row in rows:
      echo row.join("\t")
  else:
    echo table(@["Host", "Projects", "Languages"], rows)
