## runtime.nim — direnv-compatible `.envrc` loader.
##
## Runtime model mirrors direnv exactly:
##   - `.envrc` is executable bash; the source of truth is the file itself.
##   - The traveling state is `WING_DIFF`, a *reversible* diff (Prev = original
##     values, Next = applied values) that lives in the shell environment.
##   - On each prompt the hook calls `wing env export <shell>`, which:
##       1. reads the current environment (inherited from the shell);
##       2. reverts the previous overlay via WING_DIFF -> pristine baseline;
##       3. re-runs `.envrc` in a bash subshell against that pristine baseline;
##       4. diffs current-vs-new and emits shell code (export/unset) for the
##          shell to eval;
##       5. updates WING_DIFF to the new reversible diff.
##   - Running against the pristine baseline is what prevents accumulation
##     (e.g. PATH growing on every cycle) and makes unload restore originals.
##
## direnv is MIT-licensed; this is an independent Nim implementation that ships
## a trimmed copy of direnv's stdlib (see stdlib.sh) for `.envrc` parity.

import std/[base64, md5, os, osproc, streams, strutils, strtabs, tables]

import ../storage

const
  EnvrcName* = ".envrc"
  DiffMarker* = "WING_DIFF"
  StdlibSrc* = staticRead("stdlib.sh")
  StdlibVersion* = "1" # bump to force stdlib refresh on disk

type
  EnvMap* = TableRef[string, string]

  EnvDiff* = object
    ## Reversible diff. `prev` holds original values (for restore/revert),
    ## `next` holds the applied values. A key in `next` only means "added";
    ## a key in `prev` only means "removed"; in both means "changed".
    prev*: EnvMap
    next*: EnvMap

const
  ## Keys excluded from diffing. NOTE: the traveling marker (WING_DIFF) is
  ## intentionally NOT ignored — it must propagate through the diff so the
  ## shell carries it between prompt cycles (mirrors direnv's DIRENV_DIFF).
  IgnoredKeys* = [
    "WING_BIN", "WING_ENVRC", "WING_ENVRC_DIR", "WING_STDLIB",
    "WING_WATCH_FILE",
    "DIRENV_IN_ENVRC", "DIRENV_DIFF", "DIRENV_DIR", "DIRENV_FILE",
    "DIRENV_WATCHES", "COMP_WORDBREAKS", "PS1", "OLDPWD", "PWD", "SHELL",
    "SHELLOPTS", "SHLVL", "_", "PIPESTATUS"
  ]
  IgnoredPrefixes* = ["__fish", "BASH_FUNC_"]

proc ignoredKey*(key: string): bool =
  if key in IgnoredKeys: return true
  for p in IgnoredPrefixes:
    if key.startsWith(p): return true
  false

proc newEnvMap*(): EnvMap = newTable[string, string]()

proc copyMap*(src: EnvMap): EnvMap =
  result = newEnvMap()
  if not src.isNil:
    for k, v in src.pairs():
      result[k] = v

proc currentEnv*(): EnvMap =
  result = newEnvMap()
  for kv in envPairs():
    if kv.key.len == 0:
      continue
    result[kv.key] = kv.value

proc toShellTable*(m: EnvMap): StringTableRef =
  result = newStringTable()
  if not m.isNil:
    for k, v in m.pairs():
      result[k] = v

# ---------------------------------------------------------------- paths ----

proc envDir*(): string =
  result = dataRoot() / "env"
  createDir(result)

proc allowDir*(): string =
  result = envDir() / "allow"
  createDir(result)

proc stdlibPath*(): string = envDir() / "stdlib.sh"

proc ensureStdlib*() =
  let path = stdlibPath()
  var refresh = false
  if not fileExists(path):
    refresh = true
  else:
    try:
      let first = readFile(path).splitLines()[0]
      if first.strip() != "# wing env stdlib v" & StdlibVersion:
        refresh = true
    except CatchableError:
      refresh = true
  if refresh:
    atomicWriteFile(path, "# wing env stdlib v" & StdlibVersion & "\n" &
        StdlibSrc)

proc allowFile*(envrcAbs: string): string =
  allowDir() / getMD5(envrcAbs)

proc findEnvrc*(startDir: string): string =
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

proc isAllowed*(envrcAbs: string): bool =
  let allowed = try: readFile(allowFile(envrcAbs)).strip() except CatchableError: ""
  if allowed.len == 0:
    return false
  getMD5(readFile(envrcAbs)) == allowed

# ----------------------------------------------------------- diff codec ----

proc buildDiff*(a, b: EnvMap): EnvDiff =
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

proc revert*(env: EnvMap, diff: EnvDiff): EnvMap =
  ## Apply the reverse of `diff` to `env`, returning a pristine copy.
  result = copyMap(env)
  for k in diff.next.keys():
    if k in diff.prev:
      result[k] = diff.prev[k]
    else:
      result.del(k)
  result.del(DiffMarker)

proc encodeDiff*(diff: EnvDiff): string =
  ## Serialize as lines of `P\tKEY\tbase64(value)` / `N\tKEY\tbase64(value)`,
  ## then base64 the whole blob for safe storage in an env var.
  var lines: seq[string] = @[]
  for k, v in diff.prev.pairs():
    lines.add("P\t" & k & "\t" & encode(v))
  for k, v in diff.next.pairs():
    lines.add("N\t" & k & "\t" & encode(v))
  result = encode(lines.join("\n"))

proc decodeDiff*(raw: string): EnvDiff =
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

proc parseDump*(text: string): EnvMap =
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

proc shellQuote*(s: string): string =
  "'" & s.replace("'", "'\\''") & "'"

proc emitForShell*(shell: string; diff: EnvDiff): string =
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

proc runEnvrc*(envrcAbs: string, baseEnv: EnvMap): tuple[output: string; code: int] =
  ## Run `.envrc` in a bash subshell whose environment is `baseEnv` (pristine),
  ## then dump the resulting exported environment. Dynamic values are passed to
  ## the subshell via env vars so the script body is a static raw string (no
  ## escape mangling, no path injection).
  ensureStdlib()
  let env = toShellTable(baseEnv)
  env["WING_BIN"] = getAppFilename().absolutePath()
  env["WING_ENVRC"] = envrcAbs
  env["WING_ENVRC_DIR"] = parentDir(envrcAbs)
  env["WING_STDLIB"] = stdlibPath()

  const script = r"""source "$WING_STDLIB" >&2
if [ -f "$HOME/.config/wing/direnvrc" ]; then
  # shellcheck disable=SC1090
  source "$HOME/.config/wing/direnvrc" >&2
fi
cd "$WING_ENVRC_DIR" || exit 1
# shellcheck disable=SC1090
source "$WING_ENVRC" >&2
# Re-exec wing to dump the resulting environment. The child inherits the
# post-envrc environment (avoids relying on `compgen`, which is unavailable in
# non-interactive bash on some systems).
"$WING_BIN" env dump
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
    stderr.writeLine("wing env: failed to run bash: " & e.msg)

