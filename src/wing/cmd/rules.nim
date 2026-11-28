## `wing rules` — standing instructions for coding agents, kept on the wing server: the global
## rules go to every coding tool installed here, a project's rules into its checkout's AGENTS.md.

import std/[base64, json, os, strutils]

import ../cliargs
import ../server
import ../storage
import ../store/projects
import ../ui
import ../util
import ./bundles

const RuleKind = BundleKind(plural: "rules", noun: "rules",
    manifest: "AGENTS.md", starter: "# Rules\n\n$description\n")

# Where each tool reads the rules that apply everywhere.
const GlobalFiles = [("claude", "CLAUDE.md"), ("opencode", "AGENTS.md"), (
    "gemini", "GEMINI.md"), ("codex", "AGENTS.md")]

proc statePath(): string =
  dataRoot() / "server" / "rules.json"

proc readState(): JsonNode =
  try:
    result = parseFile(statePath())
  except CatchableError:
    result = %*{"files": {}}

proc place(path, content: string; state: JsonNode;
    written: var JsonNode): string =
  ## "wrote", "same" or "left": a file wing did not write, with other words in it, is never touched.
  let ours = state{"files"} != nil and state["files"].hasKey(path)
  if fileExists(path):
    let now = readFile(path)
    if now == content:
      written[path] = %true
      return "same"
    if not ours:
      return "left"
  createDir(parentDir(path))
  writeFile(path, content)
  written[path] = %true
  "wrote"

proc pullRules*(): tuple[wrote, left: seq[string]] =
  let state = readState()
  var written = newJObject()
  let global = api("/rules/global/render")["content"].getStr()
  for (target, file) in GlobalFiles:
    if not toolInstalled(target):
      continue
    let path = toolHome(target) / file
    case place(path, global, state, written)
    of "wrote": result.wrote.add(path)
    of "left": result.left.add(path)
    else: discard
  for project in parseProjects(ensureProjectsFile()):
    if project.machine.len > 0 or project.path.len == 0 or not dirExists(project.path):
      continue
    var rendered: JsonNode
    try:
      rendered = api("/rules/" & enc(project.name) & "/render")
    except ServerError:
      continue
    if not rendered{"write"}.getBool():
      continue
    let path = project.path / "AGENTS.md"
    case place(path, rendered["content"].getStr(), state, written)
    of "wrote": result.wrote.add(path)
    of "left": result.left.add(path)
    else: discard
  # Files wing wrote that no rules write any more go too.
  if state{"files"} != nil:
    for path, _ in state["files"]:
      if not written.hasKey(path) and fileExists(path):
        removeFile(path)
        result.wrote.add(path & " (removed)")
  createDir(parentDir(statePath()))
  writeFile(statePath(), $(%*{"files": written}))

proc pushRules(name, file: string) =
  ## A file of yours becomes the rules: AGENTS.md of the global rules or of a project.
  if not fileExists(file):
    die("No file " & file, 2)
  var bundle = getBundle("rules", name)
  var files = newJArray()
  for f in bundle["files"]:
    if f["path"].getStr() != "AGENTS.md":
      files.add(f)
  files.add(%*{"path": "AGENTS.md", "mode": 0o644, "data": base64.encode(
      readFile(file))})
  discard api("/rules/" & enc(name), "PUT", %*{"files": files})

proc showRulesHelp() =
  echo heading("wing rules", "standing instructions for coding agents, from the wing server") & """


Usage: wing rules <COMMAND>

  [show] [global|PROJECT]     the rules, as they are written out
  edit [global|PROJECT]       its AGENTS.md in $EDITOR, saved back
  push global|PROJECT FILE    a file of yours becomes those rules
  pull                        write them here (also done by the hourly sync)

The global rules go to every coding tool installed here (CLAUDE.md, AGENTS.md, GEMINI.md in
each tool's folder). A project's rules go into its checkout as AGENTS.md, and only when the
project has rules written or agents chosen on the server. A file wing did not write, with other
words in it, is never touched: push it first to make it the rules.
"""

proc handleRules*(argsIn: seq[string]) =
  var args = argsIn
  if popFlag(args, ["-h", "--help"]):
    showRulesHelp()
    return
  let quiet = popFlag(args, ["-q", "--quiet"])
  let command = if args.len == 0: "show" else: args[0]
  if args.len > 0:
    args.delete(0)
  rejectUnknownOptions(args)
  try:
    case command
    of "show", "cat":
      let name = if args.len > 0: args[0] else: "global"
      let rendered = api("/rules/" & enc(name) & "/render")
      echo rendered["content"].getStr()
    of "edit":
      discard bundleCommand(RuleKind, "edit", @[if args.len > 0: args[
          0] else: "global", "AGENTS.md"])
    of "push":
      requireArgs(args, 2, "wing rules push global|PROJECT FILE")
      pushRules(args[0], args[1])
      success("Rules of " & accent(args[0]) & " are now " & args[1])
    of "pull", "sync":
      let pulled = pullRules()
      for path in pulled.wrote:
        if not quiet: echo "  " & mute("↓ ") & path.replace(getHomeDir(), "~/")
      for path in pulled.left:
        caution("Left " & path.replace(getHomeDir(), "~/") &
            " alone: it has other words in it; wing rules push to make it the rules")
      if not quiet or pulled.wrote.len > 0:
        success("Rules from " & accent(loadServer().host) & ": " &
            $pulled.wrote.len & " written")
    of "list", "ls":
      let state = readState()
      if state["files"].len == 0:
        notice("No rules written here yet: wing rules pull")
        return
      echo heading("Rules written here", $state["files"].len)
      for path, _ in state["files"]:
        echo "  " & path.replace(getHomeDir(), "~/")
    else:
      die("Unknown rules command: " & command, 2)
  except ServerError as error:
    die(error.msg)
