## `wing skill` — the skills coding agents load, kept on the wing server and linked into every
## agent's skills folder here.

import std/[json, os, strutils]

import ../cliargs
import ../server
import ../util

proc showSkillHelp() =
  echo """
Usage: wing skill <COMMAND>

Commands:
  pull [--force]          mirror the wing server's skills and link them into every agent
  link                    link the pulled skills again, without asking the server
  list                    the skills pulled here, and where they are linked
  push NAME DIR           upload a skill folder (SKILL.md and what it points at)
  push --all DIR          upload every skill folder under DIR

Pulled skills live in """ & serverSkillsRoot() & """.
They are linked into: """ & skillTargets().join(", ") & """
(WING_SKILL_TARGETS, colon-separated, replaces that list).
"""

proc report(linked: tuple[linked, removed: int; skipped: seq[string]]) =
  if linked.linked > 0 or linked.removed > 0:
    echo "Links: " & $linked.linked & " made, " & $linked.removed & " removed"
  for entry in linked.skipped:
    stderr.writeLine("wing: left " & entry & " alone: it is a real folder, not a link")

proc handleSkill*(argsIn: seq[string]) =
  var args = argsIn
  if args.len == 0 or popFlag(args, ["-h", "--help"]):
    showSkillHelp()
    return
  let command = args[0]
  args.delete(0)
  try:
    case command
    of "pull", "sync", "fetch":
      let force = popFlag(args, ["--force"])
      let quiet = popFlag(args, ["-q", "--quiet"])
      rejectUnknownOptions(args)
      let pulled = pullBundles("skills", force)
      if not quiet or pulled.changed + pulled.removed > 0:
        echo "Skills from " & loadServer().host & ": " & $pulled.changed & " updated, " &
            $pulled.kept & " unchanged, " & $pulled.removed & " removed"
      report(linkSkills())
    of "link":
      rejectUnknownOptions(args)
      report(linkSkills())
    of "list", "ls", "l":
      rejectUnknownOptions(args)
      let root = serverSkillsRoot()
      var names: seq[string]
      if dirExists(root):
        for kind, path in walkDir(root):
          if kind == pcDir and not extractFilename(path).startsWith("."):
            names.add(extractFilename(path))
      if names.len == 0:
        echo "No skills pulled; run `wing skill pull`"
        return
      for name in names:
        var places: seq[string]
        for target in skillTargets():
          if symlinkExists(target / name) and expandSymlink(target / name) == root / name:
            places.add(target.replace(getHomeDir(), "~/"))
        echo name & (if places.len > 0: paint("  " & places.join("  "), "2") else: paint("  not linked", "33"))
    of "push", "upload":
      let all = popFlag(args, ["--all"])
      rejectUnknownOptions(args)
      if all:
        requireArgs(args, 1, "wing skill push --all DIR")
        var pushed = 0
        for kind, dir in walkDir(args[0]):
          if kind == pcDir and fileExists(dir / "SKILL.md"):
            discard pushBundle("skills", extractFilename(dir), dir)
            echo "Pushed " & extractFilename(dir)
            inc pushed
        echo $pushed & " skills pushed to " & loadServer().host
      else:
        requireArgs(args, 2, "wing skill push NAME DIR")
        if not fileExists(args[1] / "SKILL.md"):
          die("No SKILL.md in " & args[1], 2)
        let answer = pushBundle("skills", args[0], args[1])
        echo "Pushed " & args[0] & " (" & answer{"hash"}.getStr()[0 ..< 8] & ")"
    else:
      die("Unknown skill command: " & command, 2)
  except ServerError as error:
    die(error.msg)
