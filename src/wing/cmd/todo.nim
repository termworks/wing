## `wing todo` and `wing plan` — a project's tasks and plans, kept on the wing server.
##
## Every task and plan belongs to one project. Which one is `--project NAME`, else WING_PROJECT,
## else the registered project whose path holds the current directory, else the name of the git
## checkout the current directory is in.

import std/[algorithm, json, os, osproc, strutils, tables]

import ../cliargs
import ../server
import ../store/projects
import ../ui
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

proc editText*(initial, hint: string): string =
  ## Text from $VISUAL or $EDITOR, the way git asks for a message.
  let path = getTempDir() / ("wing-" & $getCurrentProcessId() & ".md")
  writeFile(path, initial)
  let editor = block:
    let chosen = getEnv("VISUAL", getEnv("EDITOR"))
    if chosen.len > 0: chosen else: "vi"
  if execShellCmd(editor & " " & quoteShell(path)) != 0:
    removeFile(path)
    die("The editor did not finish; nothing was changed (" & hint & ")")
  result = readFile(path).strip(leading = false)
  removeFile(path)

proc rank(task: JsonNode): int =
  case task["state"].getStr()
  of "doing": 0
  of "todo": 1
  else: 2

proc sortTasks(rows: var seq[JsonNode]) =
  rows.sort(proc (a, b: JsonNode): int =
    result = cmp(rank(a), rank(b))
    if result == 0: result = cmp(b["priority"].getInt(), a["priority"].getInt())
    if result == 0: result = cmp(a["number"].getInt(), b["number"].getInt()))

proc taskLine*(task: JsonNode; withProject = false): string =
  let state = task["state"].getStr()
  let title = task["title"].getStr()
  var extra: seq[string]
  case task["priority"].getInt(1)
  of 2: extra.add(bad("!high"))
  of 0: extra.add(mute("low"))
  else: discard
  if withProject:
    extra.add(accent("@" & task["project_name"].getStr()))
  if task{"plan_title"}.getStr().len > 0:
    extra.add(info("+" & task["plan_title"].getStr()))
  let due = dueNote(task{"due"}.getStr(), state)
  if due.len > 0:
    extra.add(due)
  result = "  " & stateMark(state) & " " & mute(padLeft("#" & $task["number"].getInt(), 4)) & "  " &
           (if state == "done": mute(title) else: title)
  if extra.len > 0:
    result.add("  " & extra.join("  "))

proc printTasks(tasks: JsonNode; withProject = false; showDone = false;
    plan = ""; only = "") =
  var rows: seq[JsonNode]
  var done = 0
  for task in tasks:
    if plan.len > 0 and task{"plan_title"}.getStr() != plan and $task{
        "plan_number"}.getInt(-1) != plan:
      continue
    if only.len > 0 and task["state"].getStr() != only:
      continue
    if task["state"].getStr() == "done":
      inc done
      if not showDone:
        continue
    rows.add(task)
  sortTasks(rows)
  if rows.len == 0:
    echo "  " & mute(if done > 0: "nothing open; " & $done &
        " done" else: "nothing to do")
    return
  for task in rows:
    echo taskLine(task, withProject)
  if not showDone and done > 0:
    echo "  " & mute($done & " done · wing todo --done")

proc counts(tasks: JsonNode): string =
  var open, doing = 0
  for task in tasks:
    case task["state"].getStr()
    of "todo": inc open
    of "doing": inc doing
    else: discard
  $(open + doing) & " open" & (if doing > 0: " · " & $doing &
      " doing" else: "")

proc showTodoHelp() =
  echo heading("wing todo", "a project's tasks, on the wing server") & """


Usage: wing todo [COMMAND] [--project NAME]

Commands:
  [list]  [--all] [--done] [--doing] [--plan P]   open tasks (--all: every project)
  add TEXT...                 a task; TEXT takes +plan, !high and !low
  start N... | stop N...      move to doing, or back to to do
  done N...  | reopen N...
  show N                      everything about one task
  note N                      write its notes in $EDITOR
  edit N [--title T] [--notes N] [--priority high|normal|low] [--due YYYY-MM-DD|none] [--plan P|none]
  rm N...

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

proc showTask(project: string; task: JsonNode) =
  let state = task["state"].getStr()
  let due = task{"due"}.getStr()
  echo ""
  echo "  " & stateMark(state) & " " & strong(task["title"].getStr()) & "  " &
       mute("#" & $task["number"].getInt() & " in " & project)
  echo ""
  echo facts([
    ("state", state),
    ("priority", ["low", "normal", "high"][task["priority"].getInt(1)]),
    ("plan", task{"plan_title"}.getStr()),
    ("due", if due.len > 0: due & "  " & dueNote(due, state) else: ""),
    ("opened", ago(task["created"].getStr())),
    ("updated", ago(task["updated"].getStr())),
    ("done", ago(task{"done_at"}.getStr()))])
  if task["notes"].getStr().len > 0:
    echo ""
    for line in task["notes"].getStr().splitLines():
      echo "  " & mute("│ ") & line
  echo ""

proc handleTodo*(argsIn: seq[string]) =
  var args = argsIn
  if popFlag(args, ["-h", "--help"]):
    showTodoHelp()
    return
  let every = popFlag(args, ["-a", "--all"])
  let showDone = popFlag(args, ["--done"])
  let onlyDoing = popFlag(args, ["--doing"])
  let plan = popValue(args, ["--plan"])
  let command = if args.len == 0 or args[0].startsWith("-"): "list" else: args[0]
  if args.len > 0 and not args[0].startsWith("-"):
    args.delete(0)
  let only = if onlyDoing: "doing" else: ""
  try:
    case command
    of "list", "ls", "l":
      if every:
        rejectUnknownOptions(args)
        var byProject = initOrderedTable[string, JsonNode]()
        for task in allTasks():
          let name = task["project_name"].getStr()
          if name notin byProject:
            byProject[name] = newJArray()
          byProject[name].add(task)
        var shown = 0
        for name, tasks in byProject:
          var open = 0
          for task in tasks:
            if task["state"].getStr() != "done": inc open
          if open == 0 and not showDone:
            continue
          echo heading(name, counts(tasks))
          printTasks(tasks, showDone = showDone, plan = plan, only = only)
          echo ""
          inc shown
        if shown == 0:
          echo "  " & mute("nothing to do anywhere")
      else:
        let project = currentProject(args)
        rejectUnknownOptions(args)
        let tasks = projectTasks(project)
        echo heading(project, counts(tasks))
        printTasks(tasks, showDone = showDone, plan = plan, only = only)
    of "add", "a", "new":
      let project = currentProject(args)
      rejectUnknownOptions(args)
      requireArgs(args, 1, "wing todo add TEXT...")
      let task = addTask(project, args.join(" "))
      success("Added to " & accent(project))
      echo taskLine(task)
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
      showTask(project, getTask(project, number(args[0])))
    of "note", "notes":
      let project = currentProject(args)
      rejectUnknownOptions(args)
      requireArgs(args, 1, "wing todo note N")
      let task = getTask(project, number(args[0]))
      let notes = editText(task["notes"].getStr(), "task #" & args[0])
      if notes == task["notes"].getStr():
        notice("Notes unchanged")
      else:
        discard changeTask(project, number(args[0]), %*{"notes": notes})
        success("Notes of #" & args[0] & " saved")
    of "edit", "set":
      let project = currentProject(args)
      var fields = newJObject()
      let title = popValue(args, ["--title"])
      let notes = popValue(args, ["--notes"])
      let priority = popValue(args, ["--priority"])
      let due = popValue(args, ["--due"])
      let planName = popValue(args, ["--plan"])
      rejectUnknownOptions(args)
      requireArgs(args, 1, "wing todo edit N [--title T] [--notes N] [--priority P] [--due D] [--plan P]")
      if title.len > 0: fields["title"] = %title
      if notes.len > 0: fields["notes"] = %notes
      if priority.len > 0: fields["priority"] = %priorityValue(priority)
      if due.len > 0: fields["due"] = %(if due == "none": "" else: due)
      if planName.len > 0: fields["plan"] = %(if planName ==
          "none": "" else: planName)
      if fields.len == 0:
        die("Nothing to change", 2)
      echo taskLine(changeTask(project, number(args[0]), fields))
    of "rm", "remove", "delete", "del":
      let project = currentProject(args)
      rejectUnknownOptions(args)
      requireArgs(args, 1, "wing todo rm N")
      for value in args:
        removeTask(project, number(value))
        success("Removed #" & $number(value))
    else:
      die("Unknown todo command: " & command &
          " (to add a task: wing todo add " & command & " ...)", 2)
  except ServerError as error:
    die(error.msg)

proc showPlanHelp() =
  echo heading("wing plan", "a project's plans, on the wing server") & """


Usage: wing plan [COMMAND] [--project NAME]

Commands:
  [list]                      this project's plans, with how far along each is
  add TITLE... [--notes TEXT]
  show N                      a plan, its notes and its tasks
  edit N [--title T] [--notes TEXT]
  note N                      write its notes in $EDITOR
  close N | open N
  rm N                        its tasks stay, without a plan

Tasks join a plan with `wing todo add fix it +PLAN` (a plan's number or one-word title).
"""

proc planLine(plan: JsonNode): string =
  let total = plan["total"].getInt()
  let done = plan["done"].getInt()
  let state = plan["state"].getStr()
  "  " & stateMark(state) & " " & mute(padLeft("#" & $plan["number"].getInt(),
      4)) & "  " &
    bar(done, total) & " " & mute(padLeft($done & "/" & $total, 5)) & "  " &
    (if state == "closed": mute(plan["title"].getStr()) else: plan[
        "title"].getStr())

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
      var open = 0
      for plan in plans:
        if plan["state"].getStr() == "open": inc open
      echo heading(project, $open & " open plans")
      if plans.len == 0:
        echo "  " & mute("no plans · wing plan add TITLE")
      for plan in plans:
        echo planLine(plan)
    of "add", "new", "a":
      let notes = popValue(args, ["--notes"])
      rejectUnknownOptions(args)
      requireArgs(args, 1, "wing plan add TITLE...")
      let plan = addPlan(project, args.join(" "), notes)
      success("Plan #" & $plan["number"].getInt() & " added to " & accent(project))
    of "show", "info", "i":
      rejectUnknownOptions(args)
      requireArgs(args, 1, "wing plan show N")
      let plan = getPlan(project, number(args[0]))
      echo ""
      echo "  " & stateMark(plan["state"].getStr()) & " " & strong(plan["title"].getStr()) & "  " &
           mute("plan #" & $plan["number"].getInt() & " in " & project)
      echo "  " & bar(plan["done"].getInt(), plan["total"].getInt(), 24) & " " &
           mute($plan["done"].getInt() & " of " & $plan["total"].getInt() & " done")
      if plan["notes"].getStr().len > 0:
        echo ""
        for line in plan["notes"].getStr().splitLines():
          echo "  " & mute("│ ") & line
      echo ""
      printTasks(plan["tasks"], showDone = true)
      echo ""
    of "edit", "set":
      let title = popValue(args, ["--title"])
      let notes = popValue(args, ["--notes"])
      rejectUnknownOptions(args)
      requireArgs(args, 1, "wing plan edit N [--title T] [--notes TEXT]")
      var fields = newJObject()
      if title.len > 0: fields["title"] = %title
      if notes.len > 0: fields["notes"] = %notes
      if fields.len == 0:
        die("Nothing to change", 2)
      echo planLine(changePlan(project, number(args[0]), fields))
    of "note", "notes":
      rejectUnknownOptions(args)
      requireArgs(args, 1, "wing plan note N")
      let plan = getPlan(project, number(args[0]))
      let notes = editText(plan["notes"].getStr(), "plan #" & args[0])
      if notes == plan["notes"].getStr():
        notice("Notes unchanged")
      else:
        discard changePlan(project, number(args[0]), %*{"notes": notes})
        success("Notes of plan #" & args[0] & " saved")
    of "close", "done", "open", "reopen":
      rejectUnknownOptions(args)
      requireArgs(args, 1, "wing plan " & command & " N")
      let state = if command in ["close", "done"]: "closed" else: "open"
      echo planLine(changePlan(project, number(args[0]), %*{"state": state}))
    of "rm", "remove", "delete":
      rejectUnknownOptions(args)
      requireArgs(args, 1, "wing plan rm N")
      removePlan(project, number(args[0]))
      success("Removed plan #" & $number(args[0]))
    else:
      die("Unknown plan command: " & command, 2)
  except ServerError as error:
    die(error.msg)
