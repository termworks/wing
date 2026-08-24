## `wing doctor` — everything wing depends on, checked in one command.
##
## The point is not the checkmarks. It is that every failure names the command that fixes it: a
## diagnosis you have to go and interpret is a second problem, not a solution to the first.

import std/[os, osproc, streams, strutils]

import ../cliargs
import ../machines/facts
import ../remote
import ../ssh
import ../storage
import ../store/machines
import ../store/projects
import ../store/templates
import ../builtins/paths
import ../builtins/registry
import ../types
import ../util

type
  Verdict = enum
    vOk, vWarn, vFail

  Check = object
    name: string
    verdict: Verdict
    detail: string
    fix: string ## the command that makes it right, empty when there is nothing to do

proc mark(verdict: Verdict): string =
  case verdict
  of vOk: paint("✓", "32")
  of vWarn: paint("!", "33")
  of vFail: paint("✗", "31")

proc check(name: string; verdict: Verdict; detail = ""; fix = ""): Check =
  Check(name: name, verdict: verdict, detail: detail, fix: fix)

proc toolCheck(name, command, fix: string; required: bool): Check =
  let found = findExe(command)
  if found.len > 0:
    return check(name, vOk, found)
  check(name, if required: vFail else: vWarn, "not on $PATH", fix)

proc versionOf(command: string; args: seq[string]): string =
  ## First line only: every tool answers `--version` differently and most of them say too much.
  try:
    let process = startProcess(command, args = args,
        options = {poUsePath, poStdErrToStdOut})
    let output = process.outputStream.readAll()
    discard process.waitForExit()
    process.close()
    for line in output.splitLines():
      if line.strip().len > 0:
        return line.strip()
  except CatchableError:
    discard
  ""

proc toolChecks(): seq[Check] =
  result.add(toolCheck("nix", "nix",
      "install nix: https://nixos.org/download", required = false))
  result.add(toolCheck("oslo", "oslo",
      "install oslo: https://github.com/termworks/oslo", required = false))
  result.add(toolCheck("git", "git", "install git", required = true))
  result.add(toolCheck("rsync", "rsync",
      "install rsync — wing sync and machine push need it", required = false))
  result.add(toolCheck("ssh", "ssh", "install openssh", required = false))

  # git-flow and git-rel are what a generated project's `make release` calls, so their absence is
  # felt later rather than now -- which is exactly why it is worth saying now.
  result.add(toolCheck("git-flow", "git-flow",
      "install git-flow-next — new projects get main/develop from it",
      required = false))
  result.add(toolCheck("git-rel", "git-rel",
      "install git-rel — `make release` in a generated project calls it",
      required = false))

proc identityCheck(): Check =
  ## git-flow's first act in a new project is a commit, and a commit with no author fails with
  ## nothing but `exit status 128`.
  let email = execCmdEx("git config --get user.email").output.strip()
  let name = execCmdEx("git config --get user.name").output.strip()
  if email.len > 0 and name.len > 0:
    return check("git identity", vOk, name & " <" & email & ">")
  check("git identity", vWarn, "no user.name or user.email",
      "git config --global user.email you@example.com")

proc storeChecks(): seq[Check] =
  let root = dataRoot()
  if not dirExists(root):
    result.add(check("data directory", vFail, root & " does not exist", "wing init"))
    return
  result.add(check("data directory", vOk, root))

  # Each store is parsed rather than stat'd: a file that exists and does not parse is the failure
  # people actually hit, and it looks like everything is fine until something silently reads empty.
  try:
    let projects = parseProjects(ensureProjectsFile())
    result.add(check("projects.toml", vOk, $projects.len & " registered"))
  except CatchableError as err:
    result.add(check("projects.toml", vFail, err.msg, "check the file by hand"))
  try:
    let machines = parseMachines(ensureMachinesFile())
    result.add(check("machines.toml", vOk, $machines.len & " registered"))
  except CatchableError as err:
    result.add(check("machines.toml", vFail, err.msg, "check the file by hand"))
  try:
    let templates = parseTemplates(ensureTemplatesFile())
    result.add(check("templates.toml", vOk, $templates.len & " registered"))
  except CatchableError as err:
    result.add(check("templates.toml", vFail, err.msg,
        "check the file by hand"))

proc templateChecks(): seq[Check] =
  let roots = templateRoots()
  if roots.len == 0:
    return @[check("template roots", vFail, "no template tree is reachable",
        "run from a wing checkout, or `make configs` to install them")]
  result.add(check("template roots", vOk, $roots.len & ": " & roots.join(", ")))
  let specs = builtinSpecs()
  if specs.len == 0:
    result.add(check("templates", vWarn, "the roots declare nothing",
        "check template.lua in each template directory"))
  else:
    var unavailable: seq[string]
    for spec in specs:
      if not builtinTemplateAvailable(spec):
        unavailable.add(spec.name)
    if unavailable.len == 0:
      result.add(check("templates", vOk, $specs.len & " usable"))
    else:
      result.add(check("templates", vWarn,
          $specs.len & " declared, missing files: " & unavailable.join(", "),
          "the manifest names a directory that is not there"))

proc envCheck(): Check =
  ## The direnv-style loader only does anything once the shell hook is installed, and nothing about
  ## a project that silently never loads says so.
  let shell = getEnv("SHELL").extractFilename()
  if getEnv("WING_ENV_ACTIVE").len > 0 or getEnv("__wing_env_loaded").len > 0:
    return check("env hook", vOk, "loaded in this shell")
  check("env hook", vWarn, "not loaded in this shell",
      "add to your rc: eval \"$(wing env hook " &
      (if shell.len > 0: shell else: "bash") & ")\"")

proc machineChecks(timeoutMs: int; probe: bool): seq[Check] =
  let machines = parseMachines(ensureMachinesFile())
  if machines.len == 0:
    return @[check("machines", vOk, "none registered")]
  if not probe:
    return @[check("machines", vOk, $machines.len & " registered",
        "wing doctor --machines to check they answer")]

  # Every machine at once, and with a deadline: a doctor that hangs on one unreachable host is a
  # doctor nobody runs twice.
  let results = runOn(targetsFor(machines), "true", timeoutMs)
  for r in sortedByName(results):
    if r.exitCode == 0:
      result.add(check("machine " & r.machine, vOk, "answers"))
    else:
      result.add(check("machine " & r.machine, vWarn,
          r.output.strip().splitLines()[^1], "wing machine check " & r.machine & " --ssh"))

proc handleDoctor*(argsIn: seq[string]) =
  var args = argsIn
  let probe = popFlag(args, ["--machines", "--remote"])
  let timeoutValue = popValue(args, ["--timeout"], "5000")
  rejectUnknownOptions(args)
  var timeoutMs = 5000
  try:
    timeoutMs = parseInt(timeoutValue)
  except ValueError:
    die("Invalid timeout: " & timeoutValue, 2)

  var checks: seq[Check]
  checks.add(check("wing", vOk, getAppFilename()))
  checks.add(toolChecks())
  checks.add(identityCheck())
  checks.add(storeChecks())
  checks.add(templateChecks())
  checks.add(envCheck())
  checks.add(machineChecks(timeoutMs, probe))

  var failed, warned = 0
  for c in checks:
    var line = " " & mark(c.verdict) & " " & c.name
    if c.detail.len > 0:
      line.add(repeat(" ", max(1, 18 - c.name.len)) & paint(c.detail, "37"))
    echo line
    if c.verdict != vOk and c.fix.len > 0:
      echo "     " & paint("→ " & c.fix, "36")
    if c.verdict == vFail: failed.inc
    elif c.verdict == vWarn: warned.inc

  echo ""
  if failed == 0 and warned == 0:
    echo paint("Everything checks out.", "32")
  else:
    echo $failed & " failed, " & $warned & " to look at"
  quit(if failed > 0: 1 else: 0)
