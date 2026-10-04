## Aggregates every store into the sections the TUI renders.

import std/[sequtils, strutils]

import ./machines/facts
import ./projects/locate
import ./storage
import ./store/machines
import ./store/projects
import ./store/syncs
import ./builtins/install
import ./store/templates
import ./types
import ./util

proc loadDashboardData*(): DashboardData =
  let projectPath = ensureProjectsFile()
  let machinePath = ensureMachinesFile()
  let templatePath = ensureTemplatesFile()

  let projects = parseProjects(projectPath)
  let machines = parseMachines(machinePath)
  # What can actually be applied, which is the registry plus whatever the tree declares.
  #
  # `cast(gcsafe)` because the declared templates come from a Lua state the process keeps open, held
  # in module globals -- so reading them is not GC-safe by Nim's rules, and the TUI's `update` is an
  # override that must be. wing is single-threaded and that state is per-process, so the thing the
  # rule protects against cannot happen here.
  var templates: seq[Template]
  {.cast(gcsafe).}:
    templates = allTemplates(parseTemplates(templatePath))

  # What each machine answered when facts were last collected, if they ever were. A dashboard that
  # can say "aarch64, 8 cpus" without asking is worth more than one that only repeats what was typed
  # into it.
  let known = parseFacts(factsFile())

  var machineRows: seq[seq[string]] = @[]
  for machine in machines:
    var count = 0
    for project in projects:
      if machineLabel(project) == machine.name:
        count.inc
    let idx = findFacts(known, machine.name)
    machineRows.add(@[
      machine.name,
      machine.username,
      machine.hosts.mapIt(it.ip & ":" & it.port & ":" & it.iface).join(", "),
      $count,
      if idx >= 0: unknownIfEmpty(known[idx].os) else: "unknown"
    ])

  # This machine is not in the registry but holds projects, so it gets a row too: a list that
  # answers "where is everything" with everything except here is not answering.
  var localCount = 0
  for project in projects:
    if project.machine.len == 0:
      localCount.inc
  if localCount > 0:
    machineRows.add(@["local", "-", "-", $localCount, "this machine"])

  result = DashboardData(
    dataDir: dataRoot(),
    sections: @[
      DashboardSection(
        title: "Projects",
        empty: "No projects yet. Add one with: wing project add NAME --path PATH",
        headers: @["Machine", "Name", "Path", "Language"],
        rows: projects.mapIt(@[
          machineLabel(it),
          it.name,
          it.path,
          noneIfEmpty(it.language)
    ])
  ),
      DashboardSection(
        title: "Machines",
        empty: "No machines yet. Add one with: wing machine add NAME IP[:PORT][:IFACE]",
        headers: @["Name", "User", "Addresses", "Projects", "OS"],
        rows: machineRows
  ),
  DashboardSection(
    title: "Templates",
    empty: "No templates yet. Add one with: wing template add NAME --description DESC --path PATH",
    headers: @["Name", "Description", "Path", "Language"],
    rows: templates.mapIt(@[
      it.name,
      it.description,
      it.path,
      noneIfEmpty(it.language)
    ])
  ),
  DashboardSection(
    title: "Sync",
    empty: "No sync targets. Add one with: wing sync add NAME --project P --machine M --remote PATH",
    headers: @["Name", "Project", "Machine", "Remote", "Direction"],
    rows: parseSyncs(ensureSyncsFile()).mapIt(@[
      it.name,
      it.project,
      it.machine,
      it.remotePath,
      it.direction
    ])
  )
  ]
  )
