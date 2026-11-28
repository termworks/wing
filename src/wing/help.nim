## Top-level help screen and the markdown command reference.

import std/strutils

import ./cliargs
import ./ui
import ./util

proc command(name, alias, description: string): string =
  let label = if alias.len > 0: name & " " & mute(alias) else: name
  "  " & padRight(accent(label), 18) & description

proc showHelp*() =
  echo heading("wing", "projects, their tasks, and the machines they live on")
  echo ""
  let usage = "  $1  wing $2$3" % [mute("usage"), info("<command>"), mute(" [options]")]
  echo usage & mute("     ·  wing alone opens the dashboard")
  echo ""
  echo strong("Main commands:")
  echo command("new", "", "a project from a template, registered here and on the server")
  echo command("todo", "td", "the current project's tasks: add, start, done, show, note")
  echo command("plan", "pl", "the current project's plans, and how far along they are")
  echo command("project", "p", "this machine's projects: add, clone, adopt, discover, info")
  echo command("template", "t", "what projects are made from, edited on the server")
  echo command("doc", "", "the current project's docs: list, show, edit, add, rm")
  echo command("search", "", "everything on the server: projects, tasks, plans, files")
  echo command("agent", "ag", "coding-agent profiles: role, skills, allowed and banned tools")
  echo command("rules", "", "standing instructions for agents: global, and per project")
  echo command("skill", "sk", "agent skills from the server, linked into every agent")
  echo command("server", "", "log in, list the server's projects, import from git")
  echo command("status", "st", "what is uncommitted or unpushed, everywhere")
  echo ""
  echo strong("Machines:")
  echo command("machine", "m", "hosts, addresses and ssh config")
  echo command("ssh", "go", "a shell on a machine, or in a project wherever it is")
  echo command("sync", "s", "a project copied to another machine over ssh")
  echo command("where", "", "a project's path, or the ssh that reaches it")
  echo command("env", "e", "direnv-style .envrc loading")
  echo ""
  echo strong("Other commands:")
  echo command("tui", "ui", "the full-screen dashboard")
  echo command("doctor", "", "check the setup, and say what to fix")
  echo command("init", "", "set up wing's data and templates")
  echo command("data", "", "backup, restore, export, import")
  echo command("completions", "", "shell completions for bash, zsh, fish")
  echo ""
  echo mute("  -h, --help  help for any command  ·  -V, --version  ·  --about")

proc commandReferenceMarkdown*(): string =
  """
# wing command reference

## Main commands

- `wing new TEMPLATE PATH` — apply a template and register the project, here and on the server.
- `wing todo ...` — the current project's tasks, kept on the wing server.
- `wing plan ...` — the current project's plans, kept on the wing server.
- `wing skill ...` — agent skills from the wing server, linked into Claude, Codex and ~/.agents.
- `wing agent ...` — coding-agent profiles from the wing server, written for Claude Code, OpenCode, Gemini CLI and Codex.
- `wing project ...` — manage projects, discovery, import, JSON listing.
- `wing machine ...` — manage SSH hosts, SSH config, health checks.
- `wing template ...` — manage and safely apply project templates.
- `wing env ...` — direnv-compatible `.envrc` loader with shell hooks.
- `wing sync ...` — sync a registered project to a remote machine over SSH.

## Other commands

- `wing server login URL --token TOKEN` — log in to a wing server; `status`, `sync`, `logout`.
- `wing init` — initialize local wing data and register available templates.
- `wing data ...` — backup, restore, export, and import wing data.
- `wing completions SHELL` — generate bash, zsh, or fish completions.
- `wing tui` — open the terminal dashboard. Running `wing` with no arguments also opens it.
"""

proc handleHelpCommand*(argsIn: seq[string]) =
  var args = argsIn
  let man = popFlag(args, ["--man"])
  let markdown = popFlag(args, ["--markdown"])
  rejectUnknownOptions(args)
  if man:
    echo commandReferenceMarkdown()
  elif markdown:
    echo commandReferenceMarkdown()
  else:
    showHelp()
