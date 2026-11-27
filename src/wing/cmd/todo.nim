## `wing todo` and `wing plan` — a project's tasks and plans, kept on the wing server.
##
## Every task and plan belongs to one project. Which one is `--project NAME`, else WING_PROJECT,
## else the registered project whose path holds the current directory, else the name of the git
## checkout the current directory is in.

import std/[algorithm, json, os, osproc, strutils]

import ../cliargs
import ../server
import ../store/projects
import ../util

proc currentProject*(args: var seq[string]): string =
  result = popValue(args, ["-P", "--project"])
  if result.len > 0:
    return
  result = getEnv("WING_PROJECT")
  if result.len > 0:
    return
  let here = getCurrentDir()
  var best = ""
  for project in parseProjects(ensureProjectsFile()):
    if project.machine.len > 0 or project.path.len == 0:
      continue
    let root = absolutePath(expandTilde(project.path)).normalizedPath()
    if (here == root or here.startsWith(root & DirSep)) and root.len > best.len:
      best = root
      result = project.name
  if result.len > 0:
    return
  let (top, code) = execCmdEx("git rev-parse --show-toplevel")
  if code == 0 and top.strip().len > 0:
    return extractFilename(top.strip())
  die("Which project? Run this inside one, or pass --project NAME", 2)

proc number(value: string): int =
  try:
    result = parseInt(value.strip(chars = {'#', ' '}))
  except ValueError:
    die("Not a task number: " & value, 2)

const Marks = {"todo": "[ ]", "doing": "[~]", "done": "[x]"}

proc mark(state: string): string =
  for (name, sign) in Marks:
    if name == state:
      return sign
  "[?]"

proc taskLine(task: JsonNode; withProject = false): string =
  let priority = task["priority"].getInt(1)
  let flag = if priority == 2: paint("!", "1;31") & " " elif priority ==
      0: paint("·", "2") & " " else: ""
  result = mark(task["state"].getStr()) & " " & paint(align("#" & $task["number"].getInt(), 4), "2") & " " & flag &
           task["title"].getStr()
  var extra: seq[string]
  if withProject:
    extra.add("@" & task["project_name"].getStr())
  if task{"plan_title"}.getStr().len > 0:
    extra.add("+" & task["plan_title"].getStr())
  if task{"due"}.getStr().len > 0:
    extra.add("due " & task["due"].getStr())
  if extra.len > 0:
    result.add("  " & paint(extra.join("  "), "2"))

proc printTasks(tasks: JsonNode; withProject = false; showDone = false) =
  var rows: seq[JsonNode]
  for task in tasks:
    if showDone or task["state"].getStr() != "done":
      rows.add(task)
  if rows.len == 0:
    echo "Nothing to do"
    return
  rows.sort(proc (a, b: JsonNode): int =
    let rank = proc (t: JsonNode): int =
      case t["state"].getStr()
      of "doing": 0
      of "todo": 1
      else: 2
    result = cmp(rank(a), rank(b))
    if result == 0: result = cmp(b["priority"].getInt(), a["priority"].getInt())
    if result == 0: result = cmp(a["number"].getInt(), b["number"].getInt()))
  for task in rows:
    echo taskLine(task, withProject)

proc showTodoHelp() =
  echo """
Usage: wing todo [COMMAND] [--project NAME]

Commands:
  [list]  [--all] [--done]    open tasks of this project (--all: every project)
  add TEXT...                 a task; TEXT takes +plan, !high and !low
  start N | stop N            move to doing, or back to to do
  done N | reopen N
  show N
  edit N [--title T] [--notes N] [--priority high|normal|low] [--due YYYY-MM-DD] [--plan P]
  rm N

The project is the one the current directory is in, unless --project or WING_PROJECT says.
"""

proc priorityValue(value: string): int =
  case value.toLowerAscii()
  of "high", "2", "!": 2
  of "low", "0": 0
  of "normal", "1", "": 1
  else:
    die("Priority is high, normal or low", 2)
    1

proc handleTodo*(argsIn: seq[string]) =
  var args = argsIn
  if popFlag(args, ["-h", "--help"]):
    showTodoHelp()
    return
  let every = popFlag(args, ["-a", "--all"])
  let showDone = popFlag(args, ["--done"])
  let command = if args.len == 0 or args[0].startsWith("-"): "list" else: args[0]
  if args.len > 0 and not args[0].startsWith("-"):
    args.delete(0)
  try:
    case command
    of "list", "ls", "l":
      if every:
        rejectUnknownOptions(args)
        printTasks(allTasks(), withProject = true, showDone = showDone)
      else:
        let project = currentProject(args)
        rejectUnknownOptions(args)
        echo paint(project, "1")
        printTasks(projectTasks(project), showDone = showDone)
    of "add", "a", "new":
      let project = currentProject(args)
      rejectUnknownOptions(args)
      requireArgs(args, 1, "wing todo add TEXT...")
      let task = addTask(project, args.join(" "))
      echo "Added " & taskLine(task)
    of "start", "doing", "stop", "done", "finish", "close", "reopen", "open":
      let project = currentProject(args)
      rejectUnknownOptions(args)
      requireArgs(args, 1, "wing todo " & command & " N")
      let state = case command
        of "start", "doing": "doing"
        of "done", "finish", "close": "done"
        else: "todo"
      for value in args:
        echo taskLine(changeTask(project, number(value), %*{"state": state}))
    of "show", "info", "i":
      let project = currentProject(args)
      rejectUnknownOptions(args)
      requireArgs(args, 1, "wing todo show N")
      let task = getTask(project, number(args[0]))
      echo taskLine(task)
      echo paint("project ", "2") & project & paint("  priority ", "2") &
           ["low", "normal", "high"][task["priority"].getInt(1)] &
           paint("  updated ", "2") & displayStamp(task["updated"].getStr())
      if task["notes"].getStr().len > 0:
        echo ""
        echo task["notes"].getStr()
    of "edit", "set":
      let project = currentProject(args)
      var fields = newJObject()
      let title = popValue(args, ["--title"])
      let notes = popValue(args, ["--notes"])
      let priority = popValue(args, ["--priority"])
      let due = popValue(args, ["--due"])
      let plan = popValue(args, ["--plan"])
      rejectUnknownOptions(args)
      requireArgs(args, 1, "wing todo edit N [--title T] [--notes N] [--priority P] [--due D] [--plan P]")
      if title.len > 0: fields["title"] = %title
      if notes.len > 0: fields["notes"] = %notes
      if priority.len > 0: fields["priority"] = %priorityValue(priority)
      if due.len > 0: fields["due"] = %(if due == "none": "" else: due)
      if plan.len > 0: fields["plan"] = %(if plan == "none": "" else: plan)
      if fields.len == 0:
        die("Nothing to change", 2)
      echo taskLine(changeTask(project, number(args[0]), fields))
    of "rm", "remove", "delete", "del":
      let project = currentProject(args)
      rejectUnknownOptions(args)
      requireArgs(args, 1, "wing todo rm N")
      for value in args:
        removeTask(project, number(value))
        echo "Removed #" & $number(value)
    else:
      # `wing todo fix the build` reads as adding a task; anything else that is not a command is
      # more likely a typo of one, so only text with a space or a marker counts.
      die("Unknown todo command: " & command &
          " (to add a task: wing todo add " & command & " ...)", 2)
  except ServerError as error:
    die(error.msg)

proc showPlanHelp() =
  echo """
Usage: wing plan [COMMAND] [--project NAME]

Commands:
  [list]                      this project's plans, with how far along each is
  add TITLE... [--notes TEXT]
  show N                      a plan, its notes and its tasks
  close N | open N
  rm N                        its tasks stay, without a plan

Tasks join a plan with `wing todo add fix it +PLAN` (a plan's number or one-word title).
"""

proc planLine(plan: JsonNode): string =
  let total = plan["total"].getInt()
  let done = plan["done"].getInt()
  let width = 12
  let filled = if total == 0: 0 else: (done * width) div total
  result = paint(align("#" & $plan["number"].getInt(), 4), "2") & " " &
           paint(repeat("━", filled), "32") & paint(repeat("━", width -
               filled), "2") & " " &
           align($done & "/" & $total, 5) & "  " & plan["title"].getStr()
  if plan["state"].getStr() == "closed":
    result.add(paint("  closed", "2"))

proc handlePlan*(argsIn: seq[string]) =
  var args = argsIn
  if popFlag(args, ["-h", "--help"]):
    showPlanHelp()
    return
  let command = if args.len == 0 or args[0].startsWith("-"): "list" else: args[0]
  if args.len > 0 and not args[0].startsWith("-"):
    args.delete(0)
  try:
    let project = currentProject(args)
    case command
    of "list", "ls", "l":
      rejectUnknownOptions(args)
      let plans = projectPlans(project)
      echo paint(project, "1")
      if plans.len == 0:
        echo "No plans"
      for plan in plans:
        echo planLine(plan)
    of "add", "new", "a":
      let notes = popValue(args, ["--notes"])
      rejectUnknownOptions(args)
      requireArgs(args, 1, "wing plan add TITLE...")
      echo "Added " & planLine(addPlan(project, args.join(" "), notes))
    of "show", "info", "i":
      rejectUnknownOptions(args)
      requireArgs(args, 1, "wing plan show N")
      let plan = getPlan(project, number(args[0]))
      echo planLine(plan)
      if plan["notes"].getStr().len > 0:
        echo ""
        echo plan["notes"].getStr()
      echo ""
      printTasks(plan["tasks"], showDone = true)
    of "close", "done", "open", "reopen":
      rejectUnknownOptions(args)
      requireArgs(args, 1, "wing plan " & command & " N")
      let state = if command in ["close", "done"]: "closed" else: "open"
      echo planLine(changePlan(project, number(args[0]), %*{"state": state}))
    of "rm", "remove", "delete":
      rejectUnknownOptions(args)
      requireArgs(args, 1, "wing plan rm N")
      removePlan(project, number(args[0]))
      echo "Removed plan #" & $number(args[0])
    else:
      die("Unknown plan command: " & command, 2)
  except ServerError as error:
    die(error.msg)
