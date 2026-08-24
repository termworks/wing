## `wing project` — registry, discovery, and bulk import.

import std/[os, sequtils, strutils]

import ../cliargs
import ../projects/locate
import ./project_remote
import ../discovery
import ../jsonfmt
import ../store/projects
import ../types
import ../util

proc showProjectHelp() =
  echo """
Usage: wing project [--namespace NAMESPACE] <COMMAND>

Commands:
  add NAME [options]
  discover PATH [--depth N] [--json]
  import PATH [--namespace NAMESPACE] [--dry-run]
  list [--raw]
  info NAME
  set NAME [options]
  rename OLD NEW
  tag add NAME TAG
  tag remove NAME TAG
  remove NAME
"""

proc handleProject*(argsIn: seq[string]) =
  var args = argsIn
  if args.len == 0 or popFlag(args, ["-h", "--help"]):
    showProjectHelp()
    return
  let namespace = popValue(args, ["-n", "--namespace"], "default")
  requireArgs(args, 1, "wing project [--namespace NAMESPACE] <add|list|info>")
  let command = args[0]
  args.delete(0)
  let path = ensureProjectsFile()
  var projects = parseProjects(path)

  case command
  of "add", "a", "new", "create":
    let projectPath = popValue(args, ["-p", "--path"], getCurrentDir())
    let templateName = popValue(args, ["-t", "--template"])
    let description = popValue(args, ["-d", "--description"])
    let language = popValue(args, ["-l", "--language"])
    let framework = popValue(args, ["-f", "--framework"])
    let tags = popValues(args, ["--tags"])
    let onMachine = popValue(args, ["-m", "--machine"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing project add NAME [options]")
    let name = args[0]
    # The machine is part of what makes a project distinct: a `deploy` on the build server and a
    # `deploy` here are two projects, and a laptop that talks to five servers will have several
    # such pairs. Only the same name on the same machine is a duplicate.
    if projects.anyIt(it.name == name and it.namespace == namespace and
        it.machine == onMachine):
      die("Project '" & name & "' already exists on " &
          (if onMachine.len > 0: onMachine else: "this machine") &
          " in namespace '" & namespace & "'")
    let stamp = nowStamp()
    projects.add(Project(
      name: name,
      path: projectPath,
      machine: onMachine,
      namespace: namespace,
      templateName: templateName,
      description: description,
      language: language,
      framework: framework,
      tags: tags,
      createdAt: stamp,
      updatedAt: stamp
    ))
    writeProjects(path, projects)
    echo "Project '" & name & "' added successfully to namespace '" &
        namespace & "'"
  of "discover", "scan":
    let depthValue = popValue(args, ["--depth"], "3")
    let asJson = popFlag(args, ["--json"])
    let machineName = popValue(args, ["-m", "--machine"])
    let machineTags = popValues(args, ["--tag", "--tags"])
    let onAll = popFlag(args, ["--all-machines"])
    let register = popFlag(args, ["--register", "--save"])
    rejectUnknownOptions(args)
    requireArgs(args, 1,
        "wing project discover PATH [--depth N] [--machine NAME] [--register]")
    var depth = 3
    try:
      depth = parseInt(depthValue)
    except ValueError:
      die("Invalid discovery depth: " & depthValue, 2)
    if depth < 0:
      die("Invalid discovery depth: " & depthValue, 2)
    if machineName.len > 0 or onAll or machineTags.len > 0:
      discoverOnMachines(args[0], depth, machineName, machineTags, onAll, register)
      return
    if register:
      registerLocalDiscovered(args[0], depth)
      return
    printDiscovered(discoverProjects(args[0], depth), asJson)
  of "import":
    let dryRun = popFlag(args, ["--dry-run"])
    let depthValue = popValue(args, ["--depth"], "3")
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing project import PATH [--namespace NAMESPACE] [--dry-run]")
    var depth = 3
    try:
      depth = parseInt(depthValue)
    except ValueError:
      die("Invalid discovery depth: " & depthValue, 2)
    if depth < 0:
      die("Invalid discovery depth: " & depthValue, 2)
    let discovered = discoverProjects(args[0], depth)
    if discovered.len == 0:
      echo "No projects discovered"
      return
    var imported = 0
    var skipped = 0
    let stamp = nowStamp()
    for item in discovered:
      if projects.anyIt(it.name == item.name and it.namespace == namespace):
        echo "Skipped duplicate: " & item.name
        inc skipped
      elif dryRun:
        echo "Would import: " & item.name & " -> " & item.path
        inc imported
      else:
        projects.add(Project(
          name: item.name,
          path: item.path,
          namespace: namespace,
          language: item.language,
          framework: item.framework,
          tags: @[],
          createdAt: stamp,
          updatedAt: stamp
        ))
        echo "Imported: " & item.name
        inc imported
    if not dryRun and imported > 0:
      writeProjects(path, projects)
    echo "Import summary: " & $imported & " imported, " & $skipped & " skipped"
  of "list", "l", "ls":
    let raw = popFlag(args, ["-r", "--raw"])
    let asJson = popFlag(args, ["--json"])
    let onMachine = popValue(args, ["-m", "--machine"])
    let localOnly = popFlag(args, ["--local"])
    rejectUnknownOptions(args)
    var filtered = projects.filterIt(it.namespace == namespace)
    if onMachine.len > 0:
      filtered = filtered.filterIt(it.machine == onMachine)
    elif localOnly:
      filtered = filtered.filterIt(it.machine.len == 0)
    if asJson:
      printJsonArray(filtered, projectJson)
    elif raw:
      for project in filtered:
        echo hostLabel(project) & "\t" & project.name & "\t" &
            project.namespace & "\t" & project.path & "\t" &
            unknownIfEmpty(project.language)
    else:
      echo table(
        @["Host", "Name", "Path", "Language", "Tags", "Created"],
        filtered.mapIt(@[
          hostLabel(it),
          it.name,
          it.path,
          noneIfEmpty(it.language),
          if it.tags.len == 0: "None" else: it.tags.join(", "),
          dateOnly(it.createdAt)
        ])
      )
  of "info", "i", "show":
    let onMachine = popValue(args, ["-m", "--machine"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing project info NAME [--machine HOST]")
    # A name can mean a project on more than one machine, so `HOST:NAME` and `--machine` both
    # narrow it; without either, the first match still answers, as it always did.
    let (fromRef, name) = splitQualified(args[0])
    let wanted = if onMachine.len > 0: onMachine else: fromRef
    for project in projects:
      if project.name == name and project.namespace == namespace and
          (wanted.len == 0 or hostLabel(project) == wanted):
        echo "Project: " & project.name
        echo "Path: " & project.path
        echo "Host: " & hostLabel(project)
        echo "Namespace: " & project.namespace
        echo "Template: " & noneIfEmpty(project.templateName)
        echo "Description: " & noneIfEmpty(project.description)
        echo "Language: " & noneIfEmpty(project.language)
        echo "Framework: " & noneIfEmpty(project.framework)
        echo "Tags: " & (if project.tags.len ==
            0: "None" else: project.tags.join(", "))
        echo "Created: " & displayStamp(project.createdAt)
        echo "Updated: " & displayStamp(project.updatedAt)
        return
    die("Project '" & args[0] & "' not found in namespace '" & namespace & "'")
  of "remove", "rm", "delete", "del":
    let onMachine = popValue(args, ["-m", "--machine"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing project remove NAME [--machine HOST]")
    let (fromRef, name) = splitQualified(args[0])
    let wanted = if onMachine.len > 0: onMachine else: fromRef
    # Unqualified, a name can now mean a project on several machines -- and removing all of them
    # because one was asked for is not a reading anybody intended. Naming one is the way out.
    if wanted.len == 0:
      var hosts: seq[string]
      for project in projects:
        if project.name == name and project.namespace == namespace and
            hostLabel(project) notin hosts:
          hosts.add(hostLabel(project))
      if hosts.len > 1:
        die("'" & name & "' is on " & $hosts.len & " machines: " &
            hosts.mapIt(it & ":" & name).join(", ") &
            " — name one of those instead", 2)
    let before = projects.len
    projects = projects.filterIt(not (it.name == name and
        it.namespace == namespace and
        (wanted.len == 0 or hostLabel(it) == wanted)))
    if projects.len == before:
      die("Project '" & args[0] & "' not found in namespace '" & namespace & "'")
    writeProjects(path, projects)
    echo "Project '" & name & "' removed from namespace '" & namespace & "'"
  of "set", "update", "edit":
    let projectPath = popValue(args, ["-p", "--path"])
    let language = popValue(args, ["-l", "--language"])
    let framework = popValue(args, ["-f", "--framework"])
    let description = popValue(args, ["-d", "--description"])
    let onMachine = popValue(args, ["-m", "--machine"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing project set NAME [options]")
    if projectPath.len == 0 and language.len == 0 and framework.len == 0 and
        description.len == 0 and onMachine.len == 0:
      die("No project fields were provided", 2)
    let name = args[0]
    for i in 0 .. projects.high:
      if projects[i].name == name and projects[i].namespace == namespace:
        if projectPath.len > 0:
          projects[i].path = projectPath
        if language.len > 0:
          projects[i].language = language
        if framework.len > 0:
          projects[i].framework = framework
        if description.len > 0:
          projects[i].description = description
        # `--machine local` moves a project back to this machine, which is stored as no machine at
        # all -- otherwise there would be no way to undo a `--machine lab` except by hand.
        if onMachine.len > 0:
          projects[i].machine = if onMachine == "local": "" else: onMachine
        projects[i].updatedAt = nowStamp()
        writeProjects(path, projects)
        echo "Project '" & name & "' updated in namespace '" & namespace & "'"
        return
    die("Project '" & name & "' not found in namespace '" & namespace & "'")
  of "rename", "mv":
    rejectUnknownOptions(args)
    requireArgs(args, 2, "wing project rename OLD NEW")
    let oldName = args[0]
    let newName = args[1]
    if projects.anyIt(it.name == newName and it.namespace == namespace):
      die("Project '" & newName & "' already exists in namespace '" &
          namespace & "'")
    for i in 0 .. projects.high:
      if projects[i].name == oldName and projects[i].namespace == namespace:
        projects[i].name = newName
        projects[i].updatedAt = nowStamp()
        writeProjects(path, projects)
        echo "Project '" & oldName & "' renamed to '" & newName &
            "' in namespace '" & namespace & "'"
        return
    die("Project '" & oldName & "' not found in namespace '" & namespace & "'")
  of "tag", "tags":
    rejectUnknownOptions(args)
    requireArgs(args, 3, "wing project tag add|remove NAME TAG")
    let action = args[0]
    let name = args[1]
    let tag = args[2]
    for i in 0 .. projects.high:
      if projects[i].name == name and projects[i].namespace == namespace:
        case action
        of "add":
          if not projects[i].tags.contains(tag):
            projects[i].tags.add(tag)
        of "remove", "rm":
          projects[i].tags = projects[i].tags.filterIt(it != tag)
        else:
          die("Unknown project tag action: " & action, 2)
        projects[i].updatedAt = nowStamp()
        writeProjects(path, projects)
        echo "Project '" & name & "' tags updated in namespace '" & namespace & "'"
        return
    die("Project '" & name & "' not found in namespace '" & namespace & "'")
  else:
    die("Unknown project command: " & command, 2)
