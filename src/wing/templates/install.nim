## Fetching a template and deciding whether to keep it.
##
## The order matters: fetch to a scratch directory, read what it declares, show that, and only then
## copy it in. A template is somebody else's Lua, and the point of the manifest being readable
## before the install lands is that you can look at what it claims first.

import std/[os, osproc, streams, strutils]

import ../lua/prelude
import ../lua/vm
import ../types
import ../util
import ./manifest
import ./source

type
  Candidate* = object
    ## What an install would add, decided before anything is written.
    dir*: string
    specs*: seq[TemplateSpec]
    hash*: string
    hasLogic*: bool

proc runGit(args: seq[string]; cwd = ""): tuple[ok: bool; output: string] =
  let process = startProcess("git", workingDir = cwd, args = args,
      options = {poUsePath, poStdErrToStdOut})
  let captured = process.outputStream.readAll()
  let code = process.waitForExit()
  process.close()
  (code == 0, captured)

proc fetch*(src: Source; staging: string): string =
  ## Put the source in `staging` and answer the directory holding it.
  case src.kind
  of skPath:
    if not dirExists(src.path):
      die("Template source '" & src.path & "' does not exist", 2)
    result = src.path
  of skGit:
    if findExe("git").len == 0:
      die("git is required on PATH to install from a repository", 2)
    let clone = staging / "clone"
    let cloned = runGit(@["clone", "--quiet", src.url, clone])
    if not cloned.ok:
      die("could not clone " & src.url & "\n" & cloned.output.strip(), 2)
    # Detached at the revision named. A branch would be a different template tomorrow, and the
    # trust hash would then refuse to load it after every upstream commit.
    let checked = runGit(@["checkout", "--quiet", "--detach", src.revision], clone)
    if not checked.ok:
      die("no such revision '" & src.revision & "' in " & src.url & "\n" &
          checked.output.strip(), 2)
    result = clone

proc inspect*(dir: string): Candidate =
  ## Read what a candidate declares, without running any of its logic.
  ##
  ## The manifest is evaluated with the ordinary prelude but nothing else of wing's: it can compute
  ## and it can register, and it cannot reach the machine. `init.lua` -- where a template's real
  ## behaviour lives -- is deliberately NOT loaded here, so what you are shown before deciding to
  ## trust something is a declaration rather than the result of running it.
  let manifestPath = dir / ManifestName
  if not fileExists(manifestPath):
    die(dir & " has no " & ManifestName & ", so it is not a template", 2)

  var vm = newLuaVm()
  defer: vm.close()
  try:
    vm.run(WingPrelude, "=[wing prelude]")
    vm.run(readFile(manifestPath), "@" & manifestPath)
  except LuaError as err:
    die("that template's manifest could not be read: " & err.msg, 2)

  result.dir = dir
  result.specs = readSpecs(vm.L)
  result.hash = hashTemplate(dir)
  result.hasLogic = fileExists(dir / LogicName)
  if result.specs.len == 0:
    die(ManifestName & " declared no templates", 2)

proc copyInto*(candidate: Candidate; dest: string) =
  ## Replace `dest` with the candidate's files. A `.git` directory is left behind: what is being
  ## installed is the template, not a checkout of it.
  if dirExists(dest):
    removeDir(dest)
  createDir(dest)
  for path in walkDirRec(candidate.dir, relative = true):
    if path == ".git" or path.startsWith(".git" & DirSep):
      continue
    let target = dest / path
    createDir(parentDir(target))
    copyFile(candidate.dir / path, target)
