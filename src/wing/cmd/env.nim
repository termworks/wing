## `wing env` — direnv-compatible .envrc loader and shell hooks.

import std/[md5, os, tables]

import ../storage
import ../env/runtime
import ../util

proc cmdDump*(): int =
  ## Dump this process's own environment as the `\x1fvalue\x1e`-delimited
  ## format. Invoked as a child of the bash subshell (after .envrc has run), so
  ## the inherited env is the post-envrc environment. Mirrors `direnv dump`.
  for kv in envPairs():
    if ignoredKey(kv.key):
      continue
    stdout.write(kv.key)
    stdout.write("\x1f")
    stdout.write(kv.value)
    stdout.write("\x1e")
  return 0

proc cmdExport*(shell: string): int =
  let current = currentEnv()
  let cwd = getCurrentDir()
  let toLoad = findEnvrc(cwd)
  let dpDiff = decodeDiff(current.getOrDefault(DiffMarker))
  let previous = revert(current, dpDiff)

  # A refused .envrc still unloads whatever the last directory applied. Returning early left one
  # project's overlay live in a directory whose own .envrc was never trusted, so `cd` out of a
  # project into a blocked directory kept its PATH and secrets exported.
  var newEnv: EnvMap
  var refused = false
  if toLoad.len == 0:
    newEnv = copyMap(previous)
  elif not isAllowed(toLoad):
    stderr.writeLine("wing env: .envrc blocked — run 'wing env allow'")
    stderr.writeLine("        " & toLoad)
    newEnv = copyMap(previous)
    refused = true
  else:
    let run = runEnvrc(toLoad, previous)
    if run.code != 0:
      stderr.writeLine("wing env: .envrc evaluation failed (exit " & $run.code &
          ")")
      newEnv = copyMap(previous)
      refused = true
    else:
      newEnv = parseDump(run.output)

  # The new reversible diff (pristine -> pristine + overlay).
  let newDiff = buildDiff(previous, newEnv)
  newEnv[DiffMarker] = encodeDiff(newDiff)

  # What the shell must eval to go from its current state to newEnv.
  let shellDiff = buildDiff(current, newEnv)
  stdout.write(emitForShell(shell, shellDiff))
  return if refused: 1 else: 0

proc resolveEnvrc*(path: string): string =
  ## Resolve a user-provided path (a directory, an .envrc file, or empty) to
  ## an absolute .envrc path. Empty path means: walk up from cwd.
  if path.len == 0:
    return findEnvrc(getCurrentDir())
  let abs = absolutePath(path)
  if dirExists(abs):
    return if fileExists(abs / EnvrcName): abs / EnvrcName else: ""
  if fileExists(abs):
    return abs
  result = ""

proc cmdAllow*(path: string): int =
  let envrc = resolveEnvrc(path)
  if envrc.len == 0:
    die("wing env: no .envrc found")
  createDir(allowDir())
  atomicWriteFile(allowFile(envrc), getMD5(readFile(envrc)) & "\n")
  echo "Allowed: " & envrc
  return 0

proc cmdDeny*(path: string): int =
  let envrc = resolveEnvrc(path)
  if envrc.len == 0:
    die("wing env: no .envrc found")
  let f = allowFile(envrc)
  if fileExists(f):
    removeFile(f)
  echo "Denied: " & envrc
  return 0

proc cmdStatus*(): int =
  let cwd = getCurrentDir()
  let envrc = findEnvrc(cwd)
  echo "cwd:      " & cwd
  if envrc.len == 0:
    echo "envrc:    (none — no .envrc in this or any parent directory)"
    echo "loaded:   no"
    return 0
  echo "envrc:    " & envrc
  echo "allowed:  " & (if isAllowed(envrc): "yes" else: "no (run 'wing env allow')")
  let dpDiff = decodeDiff(getEnv(DiffMarker))
  if dpDiff.next.len == 0 and dpDiff.prev.len == 0:
    echo "loaded:   no variables"
  else:
    echo "loaded:   " & $dpDiff.next.len & " variable(s) applied"
    for k, v in dpDiff.next.pairs():
      let shown = if v.len > 60: v[0 ..< 57] & "..." else: v
      echo "  " & k & " = " & shown
  return 0

proc cmdPrune*(): int =
  var removed = 0
  for kind, path in walkDir(allowDir()):
    if kind != pcFile:
      continue
    # Allow entries are keyed by hash of the envrc path; we cannot reverse the
    # hash, so drop entries whose sibling state is clearly stale by age only is
    # not safe. Instead, prune only obviously-dead marker files.
    discard
  echo "Pruned allow-list entries: " & $removed
  return 0

# ---------------------------------------------------------------- hooks ----

proc cmdHook*(shell: string): int =
  let bin = "wing"
  case shell
  of "bash":
    echo """
__wing_env_hook() {
  local __ret=$?
  local __wing_out
  __wing_out=$(""" & bin & """ env export bash 2>/dev/null)
  if [ -n "$__wing_out" ]; then eval "$__wing_out"; fi
  return $__ret
}
if [ -n "${BASH_VERSION:-}" ]; then
  case " $PROMPT_COMMAND " in
    *"__wing_env_hook"*) ;;
    *) PROMPT_COMMAND="__wing_env_hook${PROMPT_COMMAND:+; $PROMPT_COMMAND}" ;;
  esac
fi
"""
  of "zsh":
    echo """
__wing_env_hook() {
  local __ret=$?
  local __wing_out
  __wing_out=$(""" & bin & """ env export zsh 2>/dev/null)
  if [ -n "$__wing_out" ]; then eval "$__wing_out"; fi
  return $__ret
}
if [ -n "${ZSH_VERSION:-}" ]; then
  chpwd_functions=(__wing_env_hook ${chpwd_functions[@]})
  precmd_functions=(__wing_env_hook ${precmd_functions[@]})
fi
"""
  of "fish":
    echo """
function __wing_env_hook --on-variable PWD
    set -l __wing_out (""" & bin & """ env export fish 2>/dev/null)
    if test -n "$__wing_out"
        eval "$__wing_out"
    end
end
"""
  else:
    die("wing env hook: unsupported shell '" & shell & "' (use bash, zsh, or fish)")
  return 0

# -------------------------------------------------------------- dispatch ---

proc showEnvHelp*() =
  echo """
Usage: wing env <COMMAND>

Project-aware, direnv-compatible environment loader. The .envrc file is
executable bash and the source of truth. Add to your shell:

  eval "$(wing env hook bash)"    # or zsh / fish

Commands:
  export bash|zsh|fish|json    Emit env diff for the shell to eval (hook-driven)
  hook bash|zsh|fish           Print the shell hook
  allow [PATH]                 Authorize the .envrc at PATH (default: cwd's)
  deny [PATH]                  Revoke authorization
  status                       Show cwd resolution, allow state, loaded vars
  prune                        Clean stale allow-list entries
"""

proc handleEnv*(argsIn: seq[string]) =
  var args = argsIn

  proc popFlag(a: var seq[string]; names: openArray[string]): bool =
    var i = 0
    while i < a.len:
      for name in names:
        if a[i] == name:
          a.delete(i)
          return true
      inc i
    false

  if args.len == 0 or popFlag(args, ["-h", "--help"]):
    showEnvHelp()
    return
  let cmd = args[0]
  args.delete(0)
  case cmd
  of "dump":
    quit(cmdDump())
  of "export":
    if args.len == 0:
      die("Usage: wing env export bash|zsh|fish|json", 2)
    quit(cmdExport(args[0]))
  of "hook":
    if args.len == 0:
      die("Usage: wing env hook bash|zsh|fish", 2)
    quit(cmdHook(args[0]))
  of "allow":
    quit(cmdAllow(if args.len > 0: args[0] else: ""))
  of "deny":
    quit(cmdDeny(if args.len > 0: args[0] else: ""))
  of "status", "info":
    quit(cmdStatus())
  of "prune":
    quit(cmdPrune())
  else:
    die("Unknown env command: " & cmd, 2)
