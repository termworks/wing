## `wing agent` — profiles for coding agents (role, model, skills, the tools each may call),
## kept on the wing server and written here in each installed tool's own format.

import std/[json, os, sequtils, strutils]

import ../cliargs
import ../server
import ../storage
import ../ui
import ../util
import ./bundles

const AgentKind = BundleKind(plural: "agents", noun: "agent",
             manifest: "AGENT.md", starter: "---\nname: $name\ndescription: $description\ntools:\n  allow: [read, grep, glob]\n" &
             "  deny: [bash(rm *), bash(git push*)]\ndefault: ask\n---\n\n" &
             "You are $name. Say what you are for, how you work, and what you never do.\n")

const ToolHomes = [("claude", ".claude"), ("opencode", ".config/opencode"), (
    "gemini", ".gemini"), ("codex", ".codex")]
const ToolNames = [("claude", "Claude Code"), ("opencode", "OpenCode"), (
    "gemini", "Gemini CLI"), ("codex", "Codex")]

proc toolName(target: string): string =
  for (key, name) in ToolNames:
    if key == target: return name
  target

proc installed*(target: string): bool =
  ## A tool is here when its own folder is: wing writes for tools you have, and makes none.
  for (key, dir) in ToolHomes:
    if key == target:
      return dirExists(getHomeDir() / dir)

proc statePath(): string =
  dataRoot() / "server" / "agents.json"

proc readState*(): JsonNode =
  try:
    result = parseFile(statePath())
  except CatchableError:
    result = %*{"files": {}, "agents": {}}

proc pullAgents*(verbose = false): tuple[written, removed, skipped: int] =
  ## Every agent on the server, written for every tool installed here. Files wing wrote before
  ## and no agent writes now are removed; a file wing did not write is never touched.
  let listing = listBundles("agents")
  var state = readState()
  let before = state{"files"}
  var files = newJObject()
  var agents = newJObject()
  let home = getHomeDir()
  for entry in listing:
    let name = entry["name"].getStr()
    if name.len == 0 or name.contains('/') or name.startsWith("."):
      continue
    let rendered = api("/agents/" & enc(name) & "/render")
    var wrote: seq[string]
    var notes = 0
    for target, made in rendered["targets"]:
      if not installed(target):
        continue
      let rel = made["path"].getStr()
      if rel.startsWith("/") or ".." in rel.split('/'):
        continue
      let path = home / rel
      if fileExists(path) and (before == nil or not before.hasKey(rel)):
        caution("Left ~/" & rel & " alone: wing did not write it")
        inc result.skipped
        continue
      createDir(parentDir(path))
      writeFile(path, made["content"].getStr())
      files[rel] = %name
      wrote.add(target)
      notes += made["notes"].len
      if verbose:
        for note in made["notes"]:
          echo "    " & mute(toolName(target) & ": " & note.getStr())
    inc result.written
    agents[name] = %*{"description": rendered["profile"]["description"].getStr(
      ), "targets": wrote, "notes": notes}
  if before != nil:
    for rel, _ in before:
      if not files.hasKey(rel) and fileExists(home / rel):
        removeFile(home / rel)
        inc result.removed
  state["files"] = files
  state["agents"] = agents
  createDir(parentDir(statePath()))
  writeFile(statePath(), $state)

proc showAgentHelp() =
  echo heading("wing agent", "profiles for coding agents, from the wing server") & """


Usage: wing agent <COMMAND>

Here:
  pull [--notes]              write every agent for each coding tool installed here
  list                        the agents written here, and for which tools

On the wing server (where agents are edited):
  remote                      every agent there
  show NAME                   an agent's files
  new NAME [DESCRIPTION...]   make one, starting with an AGENT.md
  edit NAME [FILE]            its AGENT.md (or FILE) in $EDITOR, saved back
  delete NAME [--yes]         remove it there
  push NAME DIR | --all DIR   upload agent folders

An AGENT.md holds the role (description), model, skills, and tool rules:
  tools: { allow: [read, bash(git diff *)], ask: [write], deny: [edit, bash(rm *)] }
  default: ask
Deny wins over ask, ask over allow. Each tool gets its own format: Claude Code
(~/.claude/agents), OpenCode (~/.config/opencode/agents), Gemini CLI (~/.gemini/agents)
and Codex (~/.codex/NAME.config.toml). What a tool cannot express is listed with --notes.
"""

proc handleAgent*(argsIn: seq[string]) =
  var args = argsIn
  if args.len == 0 or popFlag(args, ["-h", "--help"]):
    showAgentHelp()
    return
  let command = args[0]
  args.delete(0)
  let yes = popFlag(args, ["-y", "--yes"])
  if command in ["remote", "server", "show", "cat", "new", "create", "edit", "delete"]:
    rejectUnknownOptions(args)
    discard bundleCommand(AgentKind, command, args, yes)
    return
  try:
    case command
    of "pull", "sync", "fetch":
      let verbose = popFlag(args, ["--notes", "-v", "--verbose"])
      rejectUnknownOptions(args)
      let pulled = pullAgents(verbose)
      success("Agents from $1: $2 written, $3 removed" % [accent(loadServer(
        ).host), $pulled.written, $pulled.removed])
      let state = readState()
      for name, agent in state["agents"]:
        let targets = agent["targets"].getElems().mapIt(toolName(it.getStr()))
        let notes = agent["notes"].getInt()
        var where = mute("no tool installed")
        if targets.len > 0:
          where = targets.join(", ")
        if notes > 0 and not verbose:
          where.add(mute("  " & $notes & " notes · --notes"))
        echo "  " & accent("◆ ") & name.padRight(16) & where
    of "list", "ls", "l":
      rejectUnknownOptions(args)
      let state = readState()
      if state["agents"].len == 0:
        notice("No agents here yet: wing agent pull")
        return
      echo heading("Agents here", $state["agents"].len)
      var rows: seq[seq[string]]
      for name, agent in state["agents"]:
        var marks: seq[string]
        for (target, _) in ToolHomes:
          let has = agent["targets"].getElems().anyIt(it.getStr() == target)
          marks.add(if has: good("●") elif installed(target): bad(
              "○") else: mute("·"))
        rows.add(@[name] & marks & @[clip(agent["description"].getStr(), 60)])
      echo table(@["Agent", "claude", "opencode", "gemini", "codex", "Role"], rows)
    of "push", "upload":
      let all = popFlag(args, ["--all"])
      rejectUnknownOptions(args)
      if all:
        requireArgs(args, 1, "wing agent push --all DIR")
        var pushed = 0
        for kind, dir in walkDir(args[0]):
          if kind == pcDir and fileExists(dir / "AGENT.md"):
            discard pushBundle("agents", extractFilename(dir), dir)
            echo "  " & mute("↑ ") & extractFilename(dir)
            inc pushed
        success($pushed & " agents pushed to " & accent(loadServer().host))
      else:
        requireArgs(args, 2, "wing agent push NAME DIR")
        if not fileExists(args[1] / "AGENT.md"):
          die("No AGENT.md in " & args[1], 2)
        discard pushBundle("agents", args[0], args[1])
        success("Pushed " & accent(args[0]))
    else:
      die("Unknown agent command: " & command, 2)
  except ServerError as error:
    die(error.msg)
