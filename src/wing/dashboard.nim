## Aggregates every store into the sections the TUI renders.

import std/[sequtils, strutils]

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

  var machineRows: seq[seq[string]] = @[]
  for machine in machines:
    machineRows.add(@[
      machine.name,
      machine.username,
      machine.hosts.mapIt(it.ip & ":" & it.port & ":" & it.iface).join(", "),
      noneIfEmpty(machine.key)
    ])

  result = DashboardData(
    dataDir: dataRoot(),
    sections: @[
      DashboardSection(
        title: "Projects",
        empty: "No projects yet. Add one with: wing project add NAME --path PATH",
        headers: @["Name", "Namespace", "Path", "Language"],
        rows: projects.mapIt(@[
          it.name,
          it.namespace,
          it.path,
          noneIfEmpty(it.language)
    ])
  ),
      DashboardSection(
        title: "Machines",
        empty: "No machines yet. Add one with: wing machine add NAME IP[:PORT][:IFACE]",
        headers: @["Name", "User", "Hosts", "Key"],
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
