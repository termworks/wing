## `wing skill` — the skills coding agents load, kept on the wing server and linked into every
## agent's skills folder here.

import std/[json, os, sequtils, strutils]

import ../cliargs
import ../server
import ../ui
import ../util
import ./bundles

const SkillKind = BundleKind(plural: "skills", noun: "skill",
             manifest: "SKILL.md", starter: "---\nname: $name\ndescription: $description\n---\n\n# $name\n\n" &
             "What this skill is for, and the steps an agent follows when it is used.\n")

proc showSkillHelp() =
  echo heading("wing skill", "what coding agents load, from the wing server") &
      """


Usage: wing skill <COMMAND>

Here:
  pull [--force] [--quiet]    mirror the server's skills and link them into every agent
  list                        the skills here, and which agents see them
  link                        link them again, without asking the server

On the wing server (where skills are edited):
  remote                      every skill there
  show NAME                   a skill's files
  new NAME [DESCRIPTION...]   make one, starting with a SKILL.md
  edit NAME [FILE]            one of its files in $EDITOR (default SKILL.md), saved back
  delete NAME [--yes]         remove it there, for every machine
  push NAME DIR               upload a skill folder (SKILL.md and what it points at)
  push --all DIR              upload every skill folder under DIR

Pulled skills live in """ & serverSkillsRoot() & """
and are linked into """ & skillTargets().mapIt(it.replace(getHomeDir(),
      "~/")).join(", ") & """
(WING_SKILL_TARGETS, colon-separated, replaces that list).
"""

proc report(linked: tuple[linked, removed: int; skipped: seq[string]]) =
  if linked.linked > 0 or linked.removed > 0:
    notice("Links: " & $linked.linked & " made, " & $linked.removed & " removed")
  for entry in linked.skipped:
    caution("Left " & entry.replace(getHomeDir(), "~/") & " alone: a real folder, not a link")

proc handleSkill*(argsIn: seq[string]) =
  var args = argsIn
  if args.len == 0 or popFlag(args, ["-h", "--help"]):
    showSkillHelp()
    return
  let command = args[0]
  args.delete(0)
  let yes = popFlag(args, ["-y", "--yes"])
  if command in ["remote", "server", "show", "cat", "new", "create", "edit", "delete"]:
    rejectUnknownOptions(args)
    discard bundleCommand(SkillKind, command, args, yes)
    return
  try:
    case command
    of "pull", "sync", "fetch":
      let force = popFlag(args, ["--force"])
      let quiet = popFlag(args, ["-q", "--quiet"])
      rejectUnknownOptions(args)
      let pulled = pullBundles("skills", force)
      if not quiet or pulled.changed + pulled.removed > 0:
        success("Skills from $1: $2 updated, $3 unchanged, $4 removed" % [
            accent(loadServer().host), $pulled.changed, $pulled.kept,
                $pulled.removed])
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
        notice("No skills here yet: wing skill pull")
        return
      let targets = skillTargets()
      echo heading("Skills here", $names.len & " · linked into " &
          $targets.len & " agents")
      var rows: seq[seq[string]]
      for name in names:
        var marks: seq[string]
        for target in targets:
          let linked = symlinkExists(target / name) and expandSymlink(target /
              name) == root / name
          marks.add(if linked: good("●") else: bad("○"))
        rows.add(@[name] & marks)
      var head = @["Skill"]
      for target in targets:
        head.add(extractFilename(parentDir(target)).strip(chars = {'.'}))
      echo table(head, rows)
    of "push", "upload":
      let all = popFlag(args, ["--all"])
      rejectUnknownOptions(args)
      if all:
        requireArgs(args, 1, "wing skill push --all DIR")
        var pushed = 0
        for kind, dir in walkDir(args[0]):
          if kind == pcDir and fileExists(dir / "SKILL.md"):
            discard pushBundle("skills", extractFilename(dir), dir)
            echo "  " & mute("↑ ") & extractFilename(dir)
            inc pushed
        success($pushed & " skills pushed to " & accent(loadServer().host))
      else:
        requireArgs(args, 2, "wing skill push NAME DIR")
        if not fileExists(args[1] / "SKILL.md"):
          die("No SKILL.md in " & args[1], 2)
        let answer = pushBundle("skills", args[0], args[1])
        success("Pushed " & accent(args[0]) & mute("  " & answer{"hash"}.getStr(
          )[0 ..< 8]))
    else:
      die("Unknown skill command: " & command, 2)
  except ServerError as error:
    die(error.msg)
