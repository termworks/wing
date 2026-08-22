## `wing template` — registry, bundled template install, and apply.

import std/[os, sequtils, strutils]

import ../apply
import ../builtins/data
import ../builtins/flavours
import ../builtins/install
import ../builtins/paths
import ../cliargs
import ../jsonfmt
import ../store/templates
import ../types
import ../util

proc showTemplateHelp() =
  echo """
Usage: wing template <COMMAND>

Commands:
  add NAME --description DESC --path PATH [options]
  list [--raw]
  info NAME
  set NAME [options]
  rename OLD NEW
  tag add NAME TAG
  tag remove NAME TAG
  apply TEMPLATE TARGET_PATH [--name PROJECT_NAME] [--flavour FLAVOUR] [--dry-run] [--force|--skip-existing] [--allow-symlinks]
  builtins [list|install] [--force]
  remove NAME

Python flavours:
  nix (default), uv, pixi, micromamba

Project naming:
  A missing TARGET_PATH is created and its final component becomes the project name.
  An existing TARGET_PATH, including '.', requires --name PROJECT_NAME.
"""

proc handleTemplate*(argsIn: seq[string]) =
  var args = argsIn
  if args.len == 0 or popFlag(args, ["-h", "--help"]):
    showTemplateHelp()
    return
  let command = args[0]
  args.delete(0)
  let path = ensureTemplatesFile()
  var templates = parseTemplates(path)

  case command
  of "builtins", "builtin", "defaults":
    let force = popFlag(args, ["--force"])
    let raw = popFlag(args, ["-r", "--raw"])
    let asJson = popFlag(args, ["--json"])
    let action =
      if args.len == 0: "list"
      else:
        let value = args[0]
        args.delete(0)
        value
    rejectUnknownOptions(args)
    case action
    of "list", "ls":
      printBuiltinTemplates(builtinTemplatesRoot(), raw, asJson)
    of "install", "add", "seed":
      if raw or asJson:
        die("--raw and --json are only valid with wing template builtins list", 2)
      installBuiltinTemplates(path, templates, force)
    else:
      die("Unknown builtin template action: " & action, 2)
  of "add", "a", "new":
    let description = popValue(args, ["-d", "--description", "--desc"])
    let templatePath = popValue(args, ["-p", "--path"])
    let language = popValue(args, ["-l", "--language"])
    let framework = popValue(args, ["-f", "--framework"])
    let tags = popValues(args, ["--tags"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing template add NAME --description DESC --path PATH")
    if description.len == 0: die("Template description is required", 2)
    if templatePath.len == 0: die("Template path is required", 2)
    if not (fileExists(templatePath) or dirExists(templatePath)):
      die("Template path '" & templatePath & "' does not exist")
    let name = args[0]
    if templates.anyIt(it.name == name):
      die("Template '" & name & "' already exists")
    let stamp = nowStamp()
    templates.add(Template(
      name: name,
      description: description,
      path: templatePath,
      language: language,
      framework: framework,
      tags: tags,
      createdAt: stamp,
      updatedAt: stamp
    ))
    writeTemplates(path, templates)
    echo "Template '" & name & "' added successfully"
  of "list", "l", "ls":
    let raw = popFlag(args, ["-r", "--raw"])
    let asJson = popFlag(args, ["--json"])
    rejectUnknownOptions(args)
    if asJson:
      printJsonArray(templates, templateJson)
    elif raw:
      for tmpl in templates:
        echo tmpl.name & "\t" & unknownIfEmpty(tmpl.language) & "\t" & tmpl.path
    else:
      echo table(
        @["Name", "Description", "Language", "Framework", "Tags", "Created"],
        templates.mapIt(@[
          it.name,
          it.description,
          noneIfEmpty(it.language),
          noneIfEmpty(it.framework),
          if it.tags.len == 0: "None" else: it.tags.join(", "),
          dateOnly(it.createdAt)
        ])
      )
  of "info", "i", "show":
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing template info NAME")
    let name = args[0]
    for tmpl in templates:
      if tmpl.name == name:
        echo "Template: " & tmpl.name
        echo "Description: " & tmpl.description
        echo "Path: " & tmpl.path
        echo "Language: " & noneIfEmpty(tmpl.language)
        echo "Framework: " & noneIfEmpty(tmpl.framework)
        echo "Tags: " & (if tmpl.tags.len == 0: "None" else: tmpl.tags.join(", "))
        let builtinIndex = templateBuiltinIndex(tmpl)
        if builtinIndex >= 0 and builtinTemplateFlavours(BuiltinTemplates[
            builtinIndex]).len > 0:
          echo "Flavours: " & builtinFlavourSummary(BuiltinTemplates[
              builtinIndex])
        echo "Created: " & displayStamp(tmpl.createdAt)
        echo "Updated: " & displayStamp(tmpl.updatedAt)
        return
    die("Template '" & name & "' not found")
  of "set", "update", "edit":
    let description = popValue(args, ["-d", "--description", "--desc"])
    let templatePath = popValue(args, ["-p", "--path"])
    let language = popValue(args, ["-l", "--language"])
    let framework = popValue(args, ["-f", "--framework"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing template set NAME [options]")
    if description.len == 0 and templatePath.len == 0 and language.len == 0 and
        framework.len == 0:
      die("No template fields were provided", 2)
    if templatePath.len > 0 and not (fileExists(templatePath) or dirExists(
        templatePath)):
      die("Template path '" & templatePath & "' does not exist")
    let name = args[0]
    for i in 0 .. templates.high:
      if templates[i].name == name:
        if description.len > 0:
          templates[i].description = description
        if templatePath.len > 0:
          templates[i].path = templatePath
        if language.len > 0:
          templates[i].language = language
        if framework.len > 0:
          templates[i].framework = framework
        templates[i].updatedAt = nowStamp()
        writeTemplates(path, templates)
        echo "Template '" & name & "' updated successfully"
        return
    die("Template '" & name & "' not found")
  of "rename", "mv":
    rejectUnknownOptions(args)
    requireArgs(args, 2, "wing template rename OLD NEW")
    let oldName = args[0]
    let newName = args[1]
    if templates.anyIt(it.name == newName):
      die("Template '" & newName & "' already exists")
    for i in 0 .. templates.high:
      if templates[i].name == oldName:
        templates[i].name = newName
        templates[i].updatedAt = nowStamp()
        writeTemplates(path, templates)
        echo "Template '" & oldName & "' renamed to '" & newName & "'"
        return
    die("Template '" & oldName & "' not found")
  of "tag", "tags":
    rejectUnknownOptions(args)
    requireArgs(args, 3, "wing template tag add|remove NAME TAG")
    let action = args[0]
    let name = args[1]
    let tag = args[2]
    for i in 0 .. templates.high:
      if templates[i].name == name:
        case action
        of "add":
          if not templates[i].tags.contains(tag):
            templates[i].tags.add(tag)
        of "remove", "rm":
          templates[i].tags = templates[i].tags.filterIt(it != tag)
        else:
          die("Unknown template tag action: " & action, 2)
        templates[i].updatedAt = nowStamp()
        writeTemplates(path, templates)
        echo "Template '" & name & "' tags updated"
        return
    die("Template '" & name & "' not found")
  of "apply", "use", "create":
    let projectName = popValue(args, ["-n", "--name"])
    let flavourArgsLen = args.len
    let flavour = popValue(args, ["--flavour", "--flavor"])
    let hasFlavour = args.len != flavourArgsLen
    let dryRun = popFlag(args, ["--dry-run"])
    let force = popFlag(args, ["--force"])
    let skipExisting = popFlag(args, ["--skip-existing"])
    let allowSymlinks = popFlag(args, ["--allow-symlinks"])
    rejectUnknownOptions(args)
    requireArgs(args, 2,
        "wing template apply TEMPLATE TARGET_PATH [--name PROJECT_NAME] [--flavour FLAVOUR]")
    if force and skipExisting:
      die("--force and --skip-existing cannot be used together", 2)
    let templateName = args[0]
    let targetPath = args[1]
    var found: Template
    var hasFound = false
    for tmpl in templates:
      if tmpl.name == templateName:
        found = tmpl
        hasFound = true
        break
    if not hasFound:
      die("Template '" & templateName & "' not found")

    let source = templateSourceForFlavour(found, flavour, hasFlavour)
    let renderedName = effectiveProjectName(projectName, targetPath)
    let plan = buildTemplatePlan(source.path, targetPath, renderedName,
        allowSymlinks)
    if dryRun:
      printTemplatePlan(templateName, targetPath, source.flavour, plan)
      if plan.rejectedSymlinks.len > 0:
        die("Template contains symlinks; use --allow-symlinks")
      if plan.conflicts.len > 0 and not (force or skipExisting):
        die("Template target has conflicts; use --force or --skip-existing")
      return
    if plan.rejectedSymlinks.len > 0:
      printTemplatePlan(templateName, targetPath, source.flavour, plan)
      die("Template contains symlinks; use --allow-symlinks")
    if plan.conflicts.len > 0 and not (force or skipExisting):
      printTemplatePlan(templateName, targetPath, source.flavour, plan)
      die("Template target has conflicts; use --force or --skip-existing")

    let skippedReplacements = applyTemplate(source.path, targetPath,
        renderedName, force, skipExisting, allowSymlinks)
    printList("Skipped placeholder replacements", skippedReplacements)
    let flavourSuffix =
      if source.flavour.len > 0: " (flavour: " & source.flavour & ")"
      else: ""
    echo "Template '" & templateName & "'" & flavourSuffix &
        " successfully applied to '" & targetPath & "'"
  of "remove", "rm", "delete", "del":
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing template remove NAME")
    let name = args[0]
    let before = templates.len
    templates = templates.filterIt(it.name != name)
    if templates.len == before:
      die("Template '" & name & "' not found")
    writeTemplates(path, templates)
    echo "Template '" & name & "' removed successfully"
  else:
    die("Unknown template command: " & command, 2)
