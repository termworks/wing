## `wing new` — a project from a template, registered here and on the wing server in one step.

import std/[os, strutils]

import ../cliargs
import ../discovery
import ../util
import ./project
import "./template"

proc showNewHelp() =
  echo """
Usage: wing new TEMPLATE TARGET_PATH [options]

Applies TEMPLATE to TARGET_PATH, then registers the project (here, and on the wing server when
logged in to one). Templates come from the server: `wing template pull` refreshes them.

Options:
  --name NAME             the project's name (default: the folder's name)
  --flavour FLAVOUR       one of the template's flavours
  --namespace NAMESPACE   where it is filed (default: default)
  --description TEXT
  --tags A,B
  --no-git                leave git out
"""

proc handleNew*(argsIn: seq[string]) =
  var args = argsIn
  if args.len == 0 or popFlag(args, ["-h", "--help"]):
    showNewHelp()
    return
  let name = popValue(args, ["-n", "--name"])
  let flavour = popValue(args, ["--flavour", "--flavor"])
  let namespace = popValue(args, ["--namespace"], "default")
  let description = popValue(args, ["-d", "--description"])
  let tags = popValue(args, ["--tags"])
  let noGit = popFlag(args, ["--no-git"])
  rejectUnknownOptions(args)
  requireArgs(args, 2, "wing new TEMPLATE TARGET_PATH [--name NAME] [--flavour FLAVOUR]")
  let templateName = args[0]
  let target = absolutePath(expandTilde(args[1])).normalizedPath()
  let projectName = if name.len > 0: name else: extractFilename(target)

  var apply = @["apply", templateName, target]
  if name.len > 0: apply.add(@["--name", name])
  if flavour.len > 0: apply.add(@["--flavour", flavour])
  if noGit: apply.add("--no-git")
  handleTemplate(apply)

  var add = @["--namespace", namespace, "add", projectName, "--path", target,
      "--template", templateName]
  let detected = detectProject(target)
  if detected.found and detected.project.language.len > 0:
    add.add(@["--language", detected.project.language])
  if description.len > 0: add.add(@["--description", description])
  for tag in tags.split(','):
    if tag.strip().len > 0: add.add(@["--tags", tag.strip()])
  handleProject(add)
