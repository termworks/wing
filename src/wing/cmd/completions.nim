## `wing completions` — bash, zsh, and fish completion scripts.

import std/strutils

import ../cliargs
import ../util

proc handleCompletions*(argsIn: seq[string]) =
  var args = argsIn
  rejectUnknownOptions(args)
  requireArgs(args, 1, "wing completions bash|zsh|fish")
  let commands = "project machine template env sync init data completions tui help"
  case args[0]
  of "bash":
    echo "complete -W '" & commands & "' wing"
  of "zsh":
    echo "#compdef wing"
    echo "_arguments '1:command:(" & commands & ")'"
  of "fish":
    for command in commands.splitWhitespace():
      echo "complete -c wing -f -a " & command
  else:
    die("Unknown completion shell: " & args[0], 2)
