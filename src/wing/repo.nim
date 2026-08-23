## Putting a freshly generated project under version control.
##
## A generated project is a project from the first minute: it has a `.gitignore`, a changelog
## recipe and a `make release` that calls git. Leaving it as loose files means the first thing
## anyone does by hand is the same two commands, and the second of them is the one people forget.
##
## git-flow is the second command because the recipes assume it: `make release` runs `git-rel`,
## which refuses to work anywhere but `develop`, and the classic preset is what creates it.

import std/[os, osproc, streams, strutils]

type
  RepoSetup* = object
    initialized*: bool ## a repository was created here
    flow*: bool        ## git-flow was initialized in it
    note*: string      ## why one of those did not happen, when it did not

proc runIn(command: string; args: seq[string]; cwd: string): tuple[ok: bool;
    output: string] =
  let process = startProcess(command, workingDir = cwd, args = args,
      options = {poUsePath, poStdErrToStdOut})
  let captured = process.outputStream.readAll()
  let code = process.waitForExit()
  process.close()
  (code == 0, captured)

proc insideWorkTree(path: string): bool =
  ## Whether `path` already has version control over it -- its own repository or an enclosing one.
  ##
  ## Both count. Generating into a subdirectory of an existing checkout is a normal thing to do,
  ## and `git init` there would make a nested repository that the outer one cannot see into.
  if dirExists(path / ".git"):
    return true
  let asked = runIn("git", @["rev-parse", "--is-inside-work-tree"], path)
  asked.ok and asked.output.strip() == "true"

proc setupRepository*(path: string): RepoSetup =
  ## `git init` and `git flow init` in a generated project, unless it is already covered.
  if findExe("git").len == 0:
    return RepoSetup(note: "git is not on PATH")
  if insideWorkTree(path):
    return RepoSetup(note: "already under version control")

  let created = runIn("git", @["init", "--quiet"], path)
  if not created.ok:
    return RepoSetup(note: "git init failed: " & created.output.strip())
  result = RepoSetup(initialized: true)

  # Staged straight away, and this is not a nicety: a flake only sees files git knows about, so
  # inside a repository where nothing is tracked, `nix develop` fails with "Path 'flake.nix' ... is
  # not tracked by Git" -- and every one of these projects brings up its dev shell from `.env.lua`.
  # Staging also means git-flow's first commit is the generated project rather than an empty tree.
  let staged = runIn("git", @["add", "-A"], path)
  if not staged.ok:
    result.note = "git add failed: " & staged.output.strip()
    return

  if findExe("git-flow").len == 0:
    result.note = "git-flow is not on PATH, so main and develop were not created"
    return

  # git-flow's first act is a commit, and a commit without an author identity fails with nothing
  # but `exit status 128`. Asking first turns that into a sentence naming the fix.
  let identity = runIn("git", @["var", "GIT_AUTHOR_IDENT"], path)
  if not identity.ok:
    result.note = "git has no author identity, so main and develop were not created " &
        "(git config --global user.email you@example.com)"
    return

  # The classic preset: main, develop, and the feature/release/hotfix prefixes. `-d` takes the
  # default names rather than asking, which is the only answer that works when nobody is watching.
  let flowed = runIn("git", @["flow", "init", "-d", "--preset=classic"], path)
  if not flowed.ok:
    result.note = "git flow init failed: " & flowed.output.strip().splitLines()[
        ^1]
    return
  result.flow = true

proc describe*(setup: RepoSetup): string =
  ## One line for the end of an apply, or the empty string when there is nothing to say.
  if setup.initialized and setup.flow:
    "Initialized a git repository and git-flow (main, develop)"
  elif setup.initialized:
    "Initialized a git repository — " & setup.note
  elif setup.note.len > 0:
    "No repository was created — " & setup.note
  else:
    ""
