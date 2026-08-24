## Aggregates every store into the sections the TUI renders.

import std/[sequtils, strutils]

import ./machines/facts
import ./projects/locate
import ./storage
import ./store/machines
import ./store/projects
import ./store/syncs
import ./store/templates
import ./types
import ./util

proc loadDashboardData*(): DashboardData =
  let projectPath = ensureProjectsFile()
  let machinePath = ensureMachinesFile()
  let templatePath = ensureTemplatesFile()

  let projects = parseProjects(projectPath)
  let machines = parseMachines(machinePath)
  let templates = parseTemplates(templatePath)

  # What each machine answered when facts were last collected, if they ever were. A dashboard that
  # can say "aarch64, 8 cpus" without asking is worth more than one that only repeats what was typed
  # into it.
  let known = parseFacts(factsFile())

  var machineRows: seq[seq[string]] = @[]
  for machine in machines:
    let idx = findFacts(known, machine.name)
    machineRows.add(@[
      machine.name,
      machine.username,
      machine.hosts.mapIt(it.ip & ":" & it.port & ":" & it.iface).join(", "),
      if machine.tags.len == 0: "None" else: machine.tags.join(", "),
      if idx >= 0: unknownIfEmpty(known[idx].os) else: "unknown"
    ])

  # One row per machine that has projects, plus every registered machine that has none: "nothing
  # here yet" and "no such machine" are different answers, and only one means discovery has not run.
  var hostRows: seq[seq[string]] = @[]
  for group in byHost(projects):
    var languages: seq[string]
    for project in group.items:
      if project.language.len > 0 and project.language notin languages:
        languages.add(project.language)
    let idx = findFacts(known, group.host)
    hostRows.add(@[
      group.host,
      $group.items.len,
      languages.join(", "),
      if idx >= 0: unknownIfEmpty(known[idx].os) else: ""
    ])
  for machine in machines:
    if not hostRows.anyIt(it[0] == machine.name):
      let idx = findFacts(known, machine.name)
      hostRows.add(@[machine.name, "0", "",
          if idx >= 0: unknownIfEmpty(known[idx].os) else: ""])

  result = DashboardData(
    dataDir: dataRoot(),
    sections: @[
      DashboardSection(
        title: "Hosts",
        empty: "No hosts yet. Register machines, then: wing project discover PATH --machine NAME",
        headers: @["Host", "Projects", "Languages", "OS"],
        rows: hostRows
  ),
      DashboardSection(
        title: "Projects",
        empty: "No projects yet. Add one with: wing project add NAME --path PATH",
        headers: @["Host", "Name", "Path", "Language"],
        rows: projects.mapIt(@[
          hostLabel(it),
          it.name,
          it.path,
          noneIfEmpty(it.language)
    ])
  ),
      DashboardSection(
        title: "Machines",
        empty: "No machines yet. Add one with: wing machine add NAME IP[:PORT][:IFACE]",
        headers: @["Name", "User", "Hosts", "Tags", "OS"],
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
