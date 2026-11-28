## Aggregates every store into the sections the TUI renders.

import std/[json, os, sequtils, strutils]

import ./machines/facts
import ./projects/locate
import ./server
import ./storage
import ./store/machines
import ./store/projects
import ./store/syncs
import ./builtins/install
import ./store/templates
import ./types
import ./util

proc taskSection(server: var string; problem: var string): DashboardSection =
  ## Every project's tasks, open ones first, from the wing server.
  ## Rows: [project, number, title, state, priority, plan, due, updated].
  result = DashboardSection(title: "Tasks", headers: @["Project", "#", "Task",
      "State", "Priority", "Plan", "Due"],

empty: "Not logged in to a wing server. Log in with: wing server login URL")
  let config = loadServer()
  if not config.configured:
    return
  server = config.host
  result.empty = "Nothing to do. Add a task with a, or: wing todo add TEXT"
  var tasks: JsonNode
  try:
    {.cast(gcsafe).}:
      tasks = config.request("GET", "/api/tasks", timeout = 8)
  except CatchableError as error:
    problem = error.msg
    result.empty = config.host & " did not answer: " & error.msg
    return
  var rows: seq[seq[string]]
  for state in ["doing", "todo", "done"]:
    for t in tasks:
      if t["state"].getStr() == state:
        rows.add(@[t["project_name"].getStr(), $t["number"].getInt(), t["title"].getStr(), state,
                   ["low", "normal", "high"][t["priority"].getInt(1)], t{
                       "plan_title"}.getStr(),
                   t{"due"}.getStr(), t["updated"].getStr()])
  result.rows = rows

proc skillDescription(dir: string): string =
  ## The description line of a SKILL.md's front matter, enough for a row.
  try:
    let lines = readFile(dir / "SKILL.md").splitLines()
    for i, line in lines:
      if line.startsWith("description:"):
        result = line["description:".len .. ^1].strip(chars = {' ', '"', '\'',
            '>', '|', '-'})
        # A folded or literal block: the indented lines after it are the description.
        var j = i + 1
        while result.len == 0 and j < lines.len and (lines[j].startsWith(" ") or
            lines[j].len == 0):
          result.add(lines[j].strip() & " ")
          inc j
        while j < lines.len and lines[j].startsWith("  ") and result.len < 300:
          result.add(" " & lines[j].strip())
          inc j
        return result.strip()
  except IOError:
    discard

proc agentSection(): DashboardSection =
  ## Agents written here by `wing agent pull`. Rows: [name, tools written for, description, notes].
  result = DashboardSection(title: "Agents", headers: @["Name", "Tools", "Role",
      "Notes"],

empty: "No agents here yet. Pull them with p, or: wing agent pull")
  var state: JsonNode
  try:
    state = parseFile(dataRoot() / "server" / "agents.json")
  except CatchableError:
    return
  for name, agent in state{"agents"}:
    let targets = agent{"targets"}.getElems().mapIt(it.getStr())
    result.rows.add(@[name, targets.join(" "), agent{"description"}.getStr(),
        $agent{"notes"}.getInt()])

proc skillSection(): DashboardSection =
  ## Skills pulled from the wing server. Rows: [name, linked agents, description].
  result = DashboardSection(title: "Skills", headers: @["Name", "Linked",
      "Description"],

empty: "No skills here yet. Pull them with p, or: wing skill pull")
  let root = serverSkillsRoot()
  if not dirExists(root):
    return
  let targets = skillTargets()
  for kind, path in walkDir(root):
    let name = extractFilename(path)
    if kind != pcDir or name.startsWith("."):
      continue
    var linked: seq[string]
    for target in targets:
      if symlinkExists(target / name) and expandSymlink(target / name) == path:
        linked.add(extractFilename(parentDir(target)).strip(chars = {'.'}))
    result.rows.add(@[name, $linked.len & "/" & $targets.len & " " &
        linked.join(" "), skillDescription(path)])

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
  # The wing server's tabs: tasks beside the projects they belong to, skills beside templates.
  var server, problem: string
  result.sections.insert(taskSection(server, problem), 1)
  result.sections.insert(agentSection(), 4)
  result.sections.insert(skillSection(), 5)
  result.server = server
  result.serverError = problem
