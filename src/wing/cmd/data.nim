## `wing data` — backup, restore, export, and import of the stores.

import std/[sequtils, os]

import ../cliargs
import ../jsonfmt
import ../storage
import ../store/machines
import ../store/projects
import ../store/templates
import ../types
import ../util

proc showBackupHelp() =
  echo """
Usage: wing data backup <COMMAND>

Commands:
  create [--path PATH]
  restore PATH [--force]
"""

proc showDataHelp() =
  echo """
Usage: wing data <COMMAND>

Commands:
  backup create [--path PATH]
  backup restore PATH [--force]
  export [--format toml|json] [--path PATH]
  import PATH [--merge|--force]
"""


proc handleDataBackup(argsIn: seq[string]) =
  var args = argsIn
  if args.len == 0 or popFlag(args, ["-h", "--help"]):
    showBackupHelp()
    return

  let command = args[0]
  args.delete(0)
  case command
  of "create", "new":
    let destination = popValue(args, ["-p", "--path"])
    rejectUnknownOptions(args)
    if args.len > 0:
      die("Usage: wing data backup create [--path PATH]", 2)
    try:
      let backupPath = createBackup(destination)
      echo "Backup created: " & backupPath
    except CatchableError as e:
      die(e.msg)
  of "restore":
    let force = popFlag(args, ["--force"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing data backup restore PATH [--force]")
    try:
      restoreBackup(args[0], force)
      echo "Backup restored from: " & args[0]
    except CatchableError as e:
      die(e.msg)
  else:
    die("Unknown backup command: " & command, 2)

proc allDataJson(): string =
  let projects = parseProjects(ensureProjectsFile())
  let machines = parseMachines(ensureMachinesFile())
  let templates = parseTemplates(ensureTemplatesFile())

  proc arrayJson[T](items: seq[T]; render: proc(item: T): string): string =
    result = "["
    for i, item in items:
      if i > 0:
        result.add(", ")
      result.add(render(item))
    result.add("]")

  "{\"projects\": " & arrayJson(projects, projectJson) & ", \"machines\": " &
      arrayJson(machines, machineJson) & ", \"templates\": " &
      arrayJson(templates, templateJson) & "}"

proc handleDataExport(argsIn: seq[string]) =
  var args = argsIn
  let format = popValue(args, ["--format"], "toml")
  let destination = popValue(args, ["-p", "--path"])
  rejectUnknownOptions(args)
  if args.len > 0:
    die("Usage: wing data export [--format toml|json] [--path PATH]", 2)
  case format
  of "toml":
    try:
      let backupPath = createBackup(destination)
      echo "Exported TOML data: " & backupPath
    except CatchableError as e:
      die(e.msg)
  of "json":
    let data = allDataJson()
    if destination.len > 0:
      atomicWriteFile(destination, data & "\n")
      echo "Exported JSON data: " & destination
    else:
      echo data
  else:
    die("Unknown export format: " & format, 2)

proc mergeImport(path: string) =
  if not dirExists(path):
    die("Import path does not exist or is not a directory: " & path)

  var projects = parseProjects(ensureProjectsFile())
  for item in parseProjects(path / "projects.toml"):
    if not projects.anyIt(it.name == item.name and it.namespace ==
        item.namespace):
      projects.add(item)
  writeProjects(ensureProjectsFile(), projects)

  var machines = parseMachines(ensureMachinesFile())
  for item in parseMachines(path / "machines.toml"):
    if not machines.anyIt(it.name == item.name):
      machines.add(item)
  writeMachines(ensureMachinesFile(), machines)

  var templates = parseTemplates(ensureTemplatesFile())
  for item in parseTemplates(path / "templates.toml"):
    if not templates.anyIt(it.name == item.name):
      templates.add(item)
  writeTemplates(ensureTemplatesFile(), templates)

proc handleDataImport(argsIn: seq[string]) =
  var args = argsIn
  let force = popFlag(args, ["--force"])
  let merge = popFlag(args, ["--merge"])
  rejectUnknownOptions(args)
  requireArgs(args, 1, "wing data import PATH [--merge|--force]")
  if force and merge:
    die("--force and --merge cannot be used together", 2)
  try:
    if merge:
      mergeImport(args[0])
      echo "Import merged from: " & args[0]
    else:
      restoreBackup(args[0], force)
      echo "Import restored from: " & args[0]
  except CatchableError as e:
    die(e.msg)

proc handleData*(argsIn: seq[string]) =
  var args = argsIn
  if args.len == 0 or popFlag(args, ["-h", "--help"]):
    showDataHelp()
    return

  let command = args[0]
  args.delete(0)
  case command
  of "backup", "bk", "backups":
    handleDataBackup(args)
  of "export":
    handleDataExport(args)
  of "import":
    handleDataImport(args)
  else:
    die("Unknown data command: " & command, 2)
