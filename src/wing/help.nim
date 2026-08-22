## Top-level help screen and the markdown command reference.

import std/strutils

import ./cliargs
import ./util

proc showHelp*() =
  echo paint("wing", "1;35") & paint(" — development workflow dashboard", "2")
  echo ""
  echo paint("Usage:", "1;36") & "  " & paint("wing", "1;32") & " " &
      paint("<COMMAND>", "33")
  echo ""
  echo paint("Main commands:", "1;36")
  echo helpLine("project", "p", "Project and code creation", "1;32")
  echo helpLine("machine", "m", "Add or edit hostnames and ssh", "1;32")
  echo helpLine("template", "t", "Project template management", "1;32")
  echo helpLine("env", "e", "direnv-style .envrc loader", "1;32")
  echo helpLine("sync", "s", "Sync a project to a remote machine over SSH", "1;32")
  echo ""
  echo paint("Other commands:", "1;36")
  echo helpLine("init", "", "Initialize wing data and embedded templates",
      "1;34")
  echo helpLine("data", "", "Backup, restore, export, and import wing data",
      "1;34")
  echo helpLine("completions", "", "Generate shell completions", "1;34")
  echo helpLine("tui", "ui", "Full-screen terminal dashboard", "1;34")
  echo ""
  echo paint("Options:", "1;36")
  echo "  " & paint("--about", "33") & repeat(" ", 13) & "About the tool"
  echo "  " & paint("-h, --help", "33") & repeat(" ", 9) &
      "Print help information"
  echo "  " & paint("-V, --version", "33") & repeat(" ", 6) &
      "Print version information"
  echo ""
  echo paint("Tip:", "1;35") & " run " & paint("wing", "1;32") &
      " with no arguments to open the TUI."

proc commandReferenceMarkdown*(): string =
  """
# wing command reference

## Main commands

- `wing project ...` — manage projects, discovery, import, JSON listing.
- `wing machine ...` — manage SSH hosts, SSH config, health checks.
- `wing template ...` — manage and safely apply project templates.
- `wing env ...` — direnv-compatible `.envrc` loader with shell hooks.
- `wing sync ...` — sync a registered project to a remote machine over SSH.

## Other commands

- `wing init` — initialize local wing data and write embedded templates.
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
