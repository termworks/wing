import std/[os, osproc, strutils]

import test_support

compileBinary()

# "Where did I leave things" across the registry. The remote half needs a machine that answers, so
# these cover the local half and the reporting: what counts as worth mentioning, and what does not.
let root = "/tmp/wing-status"
resetDir(root)
let envPrefix = freshEnv("status")
let wing = wing(envPrefix)
discard checked(wing & "init")

proc git(dir: string; command: string) =
  let res = execCmdEx("git -C " & quoteShell(dir) &
      " -c user.email=t@t -c user.name=t " & command)
  doAssert res.exitCode == 0, command & "\n" & res.output

# A clean repository, a dirty one, and a directory that is not a repository at all.
for name in ["clean", "dirty"]:
  createDir(root / name)
  doAssert execCmdEx("git init -q " & quoteShell(root / name)).exitCode == 0
  writeFile(root / name / "file.txt", "one\n")
  git(root / name, "add -A")
  git(root / name, "commit -qm first")
  discard checked(wing & "project add " & name & " --path " & quoteShell(root / name))
writeFile(root / "dirty" / "file.txt", "one\ntwo\n")

createDir(root / "plain")
discard checked(wing & "project add plain --path " & quoteShell(root / "plain"))

# --- the default is quiet: only what needs attention --------------------------
let quiet = checked(wing & "status")
doAssert quiet.contains("dirty"), quiet
doAssert not quiet.contains(" clean "), "a clean repository is not worth a line by default"
doAssert quiet.contains("not a repo"), "a directory that is not a repository is worth saying"

# --- --all shows everything ---------------------------------------------------
let everything = checked(wing & "status --all")
doAssert everything.contains("clean"), everything
doAssert everything.contains("dirty"), everything

# --- a registered path that has gone away is reported, not skipped ------------
removeDir(root / "clean")
let gone = checked(wing & "status")
doAssert gone.contains("gone"), gone

# --- nothing registered is said plainly ---------------------------------------
let emptyEnv = freshEnv("status-empty")
let emptyWing = wing(emptyEnv)
discard checked(emptyWing & "init")
let nothing = checked(emptyWing & "status")
doAssert nothing.contains("No projects"), nothing
