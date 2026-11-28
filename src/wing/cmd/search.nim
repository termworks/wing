## `wing search` — one query over everything on the wing server: projects, tasks, plans, and the
## files of docs, rules, agents, skills and templates.

import std/[json, strutils]

import ../cliargs
import ../server
import ../ui
import ../util

proc lit(text, needle: string): string =
  ## The text with what was searched for picked out.
  let at = text.toLowerAscii().find(needle.toLowerAscii())
  if at < 0 or needle.len == 0:
    return text
  text[0 ..< at] & accent(text[at ..< at + needle.len]) & text[at +
      needle.len .. ^1]

proc handleSearch*(argsIn: seq[string]) =
  var args = argsIn
  if args.len == 0 or popFlag(args, ["-h", "--help"]):
    echo heading("wing search", "everything on the wing server") & "\n\nUsage: wing search WORDS...\n"
    return
  rejectUnknownOptions(args)
  let q = args.join(" ")
  try:
    let found = api("/search?q=" & enc(q))
    var total = 0
    if found["projects"].len > 0:
      echo heading("Projects")
      for p in found["projects"]:
        echo "  " & lit(p["name"].getStr(), q).padRight(24) & mute(clip(p{
            "description"}.getStr(), 70))
        inc total
    if found["tasks"].len > 0:
      echo heading("Tasks")
      for t in found["tasks"]:
        let where = mute("$1 #$2" % [t["project"].getStr(), $t["number"].getInt()])
        echo "  $1 $2  $3" % [stateMark(t["state"].getStr()), where, lit(t[
            "title"].getStr(), q)]
        inc total
    if found["plans"].len > 0:
      echo heading("Plans")
      for l in found["plans"]:
        let where = mute("$1 plan #$2" % [l["project"].getStr(), $l[
            "number"].getInt()])
        echo "  $1 $2  $3" % [stateMark(l["state"].getStr()), where, lit(l[
            "title"].getStr(), q)]
        inc total
    if found["files"].len > 0:
      echo heading("Files")
      for f in found["files"]:
        echo "  " & mute(f["kind"].getStr() & " ") & f["name"].getStr() & "/" &
            lit(f["path"].getStr(), q)
        if f["snippet"].getStr().len > 0:
          echo "      " & mute("…") & lit(clip(f["snippet"].getStr(), 100),
              q) & mute("…")
        inc total
    if total == 0:
      notice("Nothing mentions " & q)
  except ServerError as error:
    die(error.msg)
