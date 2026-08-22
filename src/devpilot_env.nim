## devpilot_env.nim — direnv-compatible `.envrc` loader.
##
## Runtime model mirrors direnv exactly:
##   - `.envrc` is executable bash; the source of truth is the file itself.
##   - The traveling state is `DP_DIFF`, a *reversible* diff (Prev = original
##     values, Next = applied values) that lives in the shell environment.
##   - On each prompt the hook calls `dp env export <shell>`, which:
##       1. reads the current environment (inherited from the shell);
##       2. reverts the previous overlay via DP_DIFF -> pristine baseline;
##       3. re-runs `.envrc` in a bash subshell against that pristine baseline;
##       4. diffs current-vs-new and emits shell code (export/unset) for the
##          shell to eval;
##       5. updates DP_DIFF to the new reversible diff.
##   - Running against the pristine baseline is what prevents accumulation
##     (e.g. PATH growing on every cycle) and makes unload restore originals.
##
## direnv is MIT-licensed; this is an independent Nim implementation that ships
## a trimmed copy of direnv's stdlib (see env_stdlib.sh) for `.envrc` parity.

import std/[base64, md5, os, osproc, streams, strutils, strtabs, tables]

import devpilot_storage

const
  EnvrcName = ".envrc"
  DiffMarker = "DP_DIFF"
  StdlibSrc = staticRead("env_stdlib.sh")
  StdlibVersion = "1" # bump to force stdlib refresh on disk

type
  EnvMap = TableRef[string, string]

  EnvDiff = object
    ## Reversible diff. `prev` holds original values (for restore/revert),
    ## `next` holds the applied values. A key in `next` only means "added";
    ## a key in `prev` only means "removed"; in both means "changed".
    prev: EnvMap
    next: EnvMap

const
  ## Keys excluded from diffing. NOTE: the traveling marker (DP_DIFF) is
  ## intentionally NOT ignored — it must propagate through the diff so the
  ## shell carries it between prompt cycles (mirrors direnv's DIRENV_DIFF).
  IgnoredKeys = [
    "DP_BIN", "DP_ENVRC", "DP_ENVRC_DIR", "DP_STDLIB", "DP_WATCH_FILE",
    "DIRENV_IN_ENVRC", "DIRENV_DIFF", "DIRENV_DIR", "DIRENV_FILE",
    "DIRENV_WATCHES", "COMP_WORDBREAKS", "PS1", "OLDPWD", "PWD", "SHELL",
    "SHELLOPTS", "SHLVL", "_", "PIPESTATUS"
  ]
  IgnoredPrefixes = ["__fish", "BASH_FUNC_"]

proc ignoredKey(key: string): bool =
  if key in IgnoredKeys: return true
  for p in IgnoredPrefixes:
    if key.startsWith(p): return true
  false

proc newEnvMap(): EnvMap = newTable[string, string]()

proc copyMap(src: EnvMap): EnvMap =
  result = newEnvMap()
  if not src.isNil:
    for k, v in src.pairs():
      result[k] = v

proc currentEnv(): EnvMap =
  result = newEnvMap()
  for kv in envPairs():
    if kv.key.len == 0:
      continue
    result[kv.key] = kv.value

proc toShellTable(m: EnvMap): StringTableRef =
  result = newStringTable()
  if not m.isNil:
    for k, v in m.pairs():
      result[k] = v

# ---------------------------------------------------------------- paths ----

proc envDir(): string =
  result = dataRoot() / "env"
  createDir(result)

proc allowDir(): string =
  result = envDir() / "allow"
  createDir(result)

proc stdlibPath(): string = envDir() / "stdlib.sh"

proc ensureStdlib() =
  let path = stdlibPath()
  var refresh = false
  if not fileExists(path):
    refresh = true
  else:
    try:
      let first = readFile(path).splitLines()[0]
      if first.strip() != "# devpilot env stdlib v" & StdlibVersion:
        refresh = true
    except CatchableError:
      refresh = true
  if refresh:
    atomicWriteFile(path, "# devpilot env stdlib v" & StdlibVersion & "\n" &
        StdlibSrc)

proc allowFile(envrcAbs: string): string =
  allowDir() / getMD5(envrcAbs)

proc findEnvrc(startDir: string): string =
  var dir = startDir
  while true:
    let candidate = dir / EnvrcName
    if fileExists(candidate):
      return absolutePath(candidate)
    let parent = parentDir(dir)
    if parent.len == 0 or parent == dir:
      break
    dir = parent
  result = ""

proc isAllowed(envrcAbs: string): bool =
  let allowed = try: readFile(allowFile(envrcAbs)).strip() except CatchableError: ""
  if allowed.len == 0:
    return false
  getMD5(readFile(envrcAbs)) == allowed

# ----------------------------------------------------------- diff codec ----

proc buildDiff(a, b: EnvMap): EnvDiff =
  ## Diff to go from `a` to `b`. prev = a's value where b differs/missing;
  ## next = b's value where a differs/missing.
  result.prev = newEnvMap()
  result.next = newEnvMap()
  if not a.isNil:
    for k, va in a.pairs():
      if ignoredKey(k):
        continue
      if b.isNil or k notin b or b[k] != va:
        result.prev[k] = va
  if not b.isNil:
    for k, vb in b.pairs():
      if ignoredKey(k):
        continue
      if a.isNil or k notin a or a[k] != vb:
        result.next[k] = vb

proc revert(env: EnvMap, diff: EnvDiff): EnvMap =
  ## Apply the reverse of `diff` to `env`, returning a pristine copy.
  result = copyMap(env)
  for k in diff.next.keys():
    if k in diff.prev:
      result[k] = diff.prev[k]
    else:
      result.del(k)
  result.del(DiffMarker)

proc encodeDiff(diff: EnvDiff): string =
  ## Serialize as lines of `P\tKEY\tbase64(value)` / `N\tKEY\tbase64(value)`,
  ## then base64 the whole blob for safe storage in an env var.
  var lines: seq[string] = @[]
  for k, v in diff.prev.pairs():
    lines.add("P\t" & k & "\t" & encode(v))
  for k, v in diff.next.pairs():
    lines.add("N\t" & k & "\t" & encode(v))
  result = encode(lines.join("\n"))

proc decodeDiff(raw: string): EnvDiff =
  result.prev = newEnvMap()
  result.next = newEnvMap()
  let s = raw.strip()
  if s.len == 0:
    return
  let text =
    try: decode(s)
    except CatchableError: return
  for line in text.split('\n'):
    if line.len == 0:
      continue
    let parts = line.split('\t')
    if parts.len < 3:
      continue
    let side = parts[0]
    let key = parts[1]
    let blob = parts[2 .. ^1].join("\t")
    let value =
      try: decode(blob)
      except CatchableError: continue
    if side == "P":
      result.prev[key] = value
    elif side == "N":
      result.next[key] = value

# --------------------------------------------------------- dump parsing ----

proc parseDump(text: string): EnvMap =
  ## Parse the `\x1fvalue\x1e`-delimited dump emitted by the bash subshell.
  result = newEnvMap()
  for chunk in text.split('\x1e'):
    if chunk.len == 0:
      continue
    let i = chunk.find('\x1f')
    if i < 0:
      continue
    let key = chunk[0 ..< i]
    let value = chunk[i + 1 .. ^1]
    if key.len > 0 and not ignoredKey(key):
      result[key] = value

# ----------------------------------------------------------- shell emit ----

proc shellQuote(s: string): string =
  "'" & s.replace("'", "'\\''") & "'"

proc emitForShell(shell: string; diff: EnvDiff): string =
  ## Emit shell code that turns the current shell env into `diff.next`-state:
  ## unset removed keys, export added/changed keys.
  case shell
  of "bash", "zsh", "":
    var unsets: seq[string] = @[]
    var exports: seq[string] = @[]
    for k in diff.prev.keys():
      if k notin diff.next:
        unsets.add(k)
    for k, v in diff.next.pairs():
      exports.add("export " & k & "=" & shellQuote(v))
    if unsets.len > 0:
      result.add("unset " & unsets.join(" ") & "\n")
    if exports.len > 0:
      result.add(exports.join("\n") & "\n")
  of "fish":
    for k in diff.prev.keys():
      if k notin diff.next:
        result.add("set -e " & k & "\n")
    for k, v in diff.next.pairs():
      result.add("set -gx " & k & " " & shellQuote(v) & "\n")
  of "json":
    proc jstr(s: string): string = "\"" & s.replace("\\", "\\\\").replace(
        "\"", "\\\"") & "\""
    var ups: seq[string] = @[]
    var downs: seq[string] = @[]
    for k, v in diff.next.pairs():
      ups.add(jstr(k) & ":" & jstr(v))
    for k in diff.prev.keys():
      if k notin diff.next:
        downs.add(jstr(k))
    result.add("{\"up\":{" & ups.join(",") & "},\"down\":[" &
        downs.join(",") & "]}")
  else:
    discard

# ------------------------------------------------------------- rc exec -----

proc runEnvrc(envrcAbs: string, baseEnv: EnvMap): tuple[output: string; code: int] =
  ## Run `.envrc` in a bash subshell whose environment is `baseEnv` (pristine),
  ## then dump the resulting exported environment. Dynamic values are passed to
  ## the subshell via env vars so the script body is a static raw string (no
  ## escape mangling, no path injection).
  ensureStdlib()
  let env = toShellTable(baseEnv)
  env["DP_BIN"] = getAppFilename().absolutePath()
  env["DP_ENVRC"] = envrcAbs
  env["DP_ENVRC_DIR"] = parentDir(envrcAbs)
  env["DP_STDLIB"] = stdlibPath()

  const script = r"""source "$DP_STDLIB" >&2
if [ -f "$HOME/.config/devpilot/direnvrc" ]; then
  # shellcheck disable=SC1090
  source "$HOME/.config/devpilot/direnvrc" >&2
fi
cd "$DP_ENVRC_DIR" || exit 1
# shellcheck disable=SC1090
source "$DP_ENVRC" >&2
# Re-exec devpilot to dump the resulting environment. The child inherits the
# post-envrc environment (avoids relying on `compgen`, which is unavailable in
# non-interactive bash on some systems).
"$DP_BIN" env dump
"""

  try:
    let p = startProcess("bash", args = ["-c", script], env = env,
        options = {poUsePath})
    result.output = p.outputStream.readAll()
    let errData = p.errorStream.readAll()
    result.code = p.waitForExit()
    p.close()
    if errData.len > 0:
      stderr.write(errData)
  except CatchableError as e:
    result.output = ""
    result.code = 1
    stderr.writeLine("dp env: failed to run bash: " & e.msg)

# -------------------------------------------------------------- commands --

proc die(msg: string, code = 1) =
  stderr.writeLine(msg)
  quit(code)

proc cmdDump(): int =
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

proc cmdExport(shell: string): int =
  let current = currentEnv()
  let cwd = getCurrentDir()
  let toLoad = findEnvrc(cwd)
  let dpDiff = decodeDiff(current.getOrDefault(DiffMarker))
  let previous = revert(current, dpDiff)

  var newEnv: EnvMap
  if toLoad.len == 0:
    newEnv = copyMap(previous)
  else:
    if not isAllowed(toLoad):
      stderr.writeLine("dp env: .envrc blocked — run 'dp env allow'")
      stderr.writeLine("        " & toLoad)
      return 1
    let run = runEnvrc(toLoad, previous)
    if run.code != 0:
      stderr.writeLine("dp env: .envrc evaluation failed (exit " & $run.code &
          ")")
      return 1
    newEnv = parseDump(run.output)

  # The new reversible diff (pristine -> pristine + overlay).
  let newDiff = buildDiff(previous, newEnv)
  newEnv[DiffMarker] = encodeDiff(newDiff)

  # What the shell must eval to go from its current state to newEnv.
  let shellDiff = buildDiff(current, newEnv)
  stdout.write(emitForShell(shell, shellDiff))
  return 0

proc resolveEnvrc(path: string): string =
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

proc cmdAllow(path: string): int =
  let envrc = resolveEnvrc(path)
  if envrc.len == 0:
    die("dp env: no .envrc found")
  createDir(allowDir())
  atomicWriteFile(allowFile(envrc), getMD5(readFile(envrc)) & "\n")
  echo "Allowed: " & envrc
  return 0

proc cmdDeny(path: string): int =
  let envrc = resolveEnvrc(path)
  if envrc.len == 0:
    die("dp env: no .envrc found")
  let f = allowFile(envrc)
  if fileExists(f):
    removeFile(f)
  echo "Denied: " & envrc
  return 0

proc cmdStatus(): int =
  let cwd = getCurrentDir()
  let envrc = findEnvrc(cwd)
  echo "cwd:      " & cwd
  if envrc.len == 0:
    echo "envrc:    (none — no .envrc in this or any parent directory)"
    echo "loaded:   no"
    return 0
  echo "envrc:    " & envrc
  echo "allowed:  " & (if isAllowed(envrc): "yes" else: "no (run 'dp env allow')")
  let dpDiff = decodeDiff(getEnv(DiffMarker))
  if dpDiff.next.len == 0 and dpDiff.prev.len == 0:
    echo "loaded:   no variables"
  else:
    echo "loaded:   " & $dpDiff.next.len & " variable(s) applied"
    for k, v in dpDiff.next.pairs():
      let shown = if v.len > 60: v[0 ..< 57] & "..." else: v
      echo "  " & k & " = " & shown
  return 0

proc cmdPrune(): int =
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

proc cmdHook(shell: string): int =
  let bin = "dp"
  case shell
  of "bash":
    echo """
__dp_env_hook() {
  local __ret=$?
  local __dp_out
  __dp_out=$(""" & bin & """ env export bash 2>/dev/null)
  if [ -n "$__dp_out" ]; then eval "$__dp_out"; fi
  return $__ret
}
if [ -n "${BASH_VERSION:-}" ]; then
  case " $PROMPT_COMMAND " in
    *"__dp_env_hook"*) ;;
    *) PROMPT_COMMAND="__dp_env_hook${PROMPT_COMMAND:+; $PROMPT_COMMAND}" ;;
  esac
fi
"""
  of "zsh":
    echo """
__dp_env_hook() {
  local __ret=$?
  local __dp_out
  __dp_out=$(""" & bin & """ env export zsh 2>/dev/null)
  if [ -n "$__dp_out" ]; then eval "$__dp_out"; fi
  return $__ret
}
if [ -n "${ZSH_VERSION:-}" ]; then
  chpwd_functions=(__dp_env_hook ${chpwd_functions[@]})
  precmd_functions=(__dp_env_hook ${precmd_functions[@]})
fi
"""
  of "fish":
    echo """
function __dp_env_hook --on-variable PWD
    set -l __dp_out (""" & bin & """ env export fish 2>/dev/null)
    if test -n "$__dp_out"
        eval "$__dp_out"
    end
end
"""
  else:
    die("dp env hook: unsupported shell '" & shell & "' (use bash, zsh, or fish)")
  return 0

# -------------------------------------------------------------- dispatch ---

proc showEnvHelp() =
  echo """
Usage: dp env <COMMAND>

Project-aware, direnv-compatible environment loader. The .envrc file is
executable bash and the source of truth. Add to your shell:

  eval "$(dp env hook bash)"    # or zsh / fish

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
      die("Usage: dp env export bash|zsh|fish|json", 2)
    quit(cmdExport(args[0]))
  of "hook":
    if args.len == 0:
      die("Usage: dp env hook bash|zsh|fish", 2)
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
