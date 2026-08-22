## `wing project` — registry, discovery, and bulk import.

import std/[os, sequtils, strutils]

import ../cliargs
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
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing project add NAME [options]")
    let name = args[0]
    if projects.anyIt(it.name == name and it.namespace == namespace):
      die("Project '" & name & "' already exists in namespace '" & namespace & "'")
    let stamp = nowStamp()
    projects.add(Project(
      name: name,
      path: projectPath,
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
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing project discover PATH [--depth N] [--json]")
    var depth = 3
    try:
      depth = parseInt(depthValue)
    except ValueError:
      die("Invalid discovery depth: " & depthValue, 2)
    if depth < 0:
      die("Invalid discovery depth: " & depthValue, 2)
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
    rejectUnknownOptions(args)
    let filtered = projects.filterIt(it.namespace == namespace)
    if asJson:
      printJsonArray(filtered, projectJson)
    elif raw:
      for project in filtered:
        echo project.name & "\t" & project.namespace & "\t" & project.path &
            "\t" & unknownIfEmpty(project.language)
    else:
      echo table(
        @["Name", "Path", "Namespace", "Template", "Language", "Framework",
            "Tags", "Created"],
        filtered.mapIt(@[
          it.name,
          it.path,
          it.namespace,
          noneIfEmpty(it.templateName),
          noneIfEmpty(it.language),
          noneIfEmpty(it.framework),
          if it.tags.len == 0: "None" else: it.tags.join(", "),
          dateOnly(it.createdAt)
        ])
      )
  of "info", "i", "show":
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing project info NAME")
    let name = args[0]
    for project in projects:
      if project.name == name and project.namespace == namespace:
        echo "Project: " & project.name
        echo "Path: " & project.path
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
    die("Project '" & name & "' not found in namespace '" & namespace & "'")
  of "remove", "rm", "delete", "del":
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing project remove NAME")
    let name = args[0]
    let before = projects.len
    projects = projects.filterIt(not (it.name == name and it.namespace == namespace))
    if projects.len == before:
      die("Project '" & name & "' not found in namespace '" & namespace & "'")
    writeProjects(path, projects)
    echo "Project '" & name & "' removed from namespace '" & namespace & "'"
  of "set", "update", "edit":
    let projectPath = popValue(args, ["-p", "--path"])
    let language = popValue(args, ["-l", "--language"])
    let framework = popValue(args, ["-f", "--framework"])
    let description = popValue(args, ["-d", "--description"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing project set NAME [options]")
    if projectPath.len == 0 and language.len == 0 and framework.len == 0 and
        description.len == 0:
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
