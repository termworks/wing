## `wing new` — a project from a template, registered here and on the wing server in one step,
## and its repository on the server's git host when asked for.

import std/[json, os, osproc, strutils]

import ../cliargs
import ../discovery
import ../server
import ../ui
import ../util
import ./project
import "./template"

proc showNewHelp() =
  echo heading("wing new", "a project from a template") & """


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
  --repo                  also make its repository on the server's git host, as origin
  --owner NAME            the repository's owner, you or an organisation (default: the namespace)
  --public                a public repository (default: private)
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
  let repo = popFlag(args, ["--repo"])
  let owner = popValue(args, ["--owner"])
  let public = popFlag(args, ["--public"])
  rejectUnknownOptions(args)
  requireArgs(args, 2, "wing new TEMPLATE TARGET_PATH [--name NAME] [--flavour FLAVOUR] [--repo]")
  if repo and not loadServer().configured:
    die("--repo needs a wing server: wing server login URL", 2)
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

  if repo:
    let who = if owner.len > 0: owner elif namespace !=
        "default": namespace else: ""
    try:
      let made = api("/projects/" & enc(projectName) & "/repo", "POST", %*{
          "owner": who, "private": not public})
      success("Repository " & accent(made["html_url"].getStr()))
      let url = made{"ssh_url"}.getStr(made{"clone_url"}.getStr())
      if dirExists(target / ".git") and url.len > 0:
        let (_, code) = execCmdEx("git -C " & quoteShell(target) &
            " remote add origin " & quoteShell(url))
        if code == 0:
          notice("origin is " & url & mute("  · git push -u origin HEAD"))
    except ServerError as error:
      caution("The project is made, its repository is not: " & error.msg)
