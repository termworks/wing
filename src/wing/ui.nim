## How wing's command-line output looks: one palette, one set of symbols, and the few shapes
## every command prints with (a heading, a row of facts, a table, a progress bar, a badge).
## Colour only reaches a terminal; NO_COLOR, TERM=dumb and pipes get plain text.

import std/[os, strutils, terminal, times, unicode]

proc colorOn*(f: File = stdout): bool =
  if getEnv("FORCE_COLOR").len > 0:
    return true
  if getEnv("NO_COLOR").len > 0 or getEnv("TERM") == "dumb":
    return false
  isatty(f)

const
  Accent* = "38;5;141" # wing's violet
  Ok* = "38;5;114"
  Warn* = "38;5;179"
  Bad* = "38;5;203"
  Info* = "38;5;117"
  Mute* = "38;5;244"
  Strong* = "1"

proc style*(text, code: string; f: File = stdout): string =
  if text.len == 0 or not colorOn(f): text else: "\e[" & code & "m" & text & "\e[0m"

proc accent*(t: string): string = style(t, Accent)
proc good*(t: string): string = style(t, Ok)
proc warning*(t: string): string = style(t, Warn)
proc bad*(t: string): string = style(t, Bad)
proc info*(t: string): string = style(t, Info)
proc mute*(t: string): string = style(t, Mute)
proc strong*(t: string): string = style(t, Strong)

proc visibleLen*(s: string): int =
  ## Columns a string takes on screen: escapes take none, every rune one.
  var i = 0
  while i < s.len:
    if s[i] == '\e':
      while i < s.len and s[i] != 'm':
        inc i
      inc i
      continue
    let rune = runeLenAt(s, i)
    inc result
    i += rune

proc padRight*(s: string; width: int): string =
  s & repeat(' ', max(0, width - visibleLen(s)))

proc padLeft*(s: string; width: int): string =
  repeat(' ', max(0, width - visibleLen(s))) & s

proc clip*(s: string; width: int): string =
  ## Plain text cut to a width, with an ellipsis where it was cut.
  if width <= 0:
    return ""
  if s.runeLen <= width:
    return s
  $s.toRunes()[0 ..< max(0, width - 1)] & "…"

proc screenWidth*(): int =
  try:
    result = terminalWidth()
  except CatchableError:
    result = 100
  if result <= 0:
    result = 100

# --- Symbols ----------------------------------------------------------------------------

proc stateMark*(state: string): string =
  case state
  of "todo": info("○")
  of "doing": warning("◐")
  of "done": good("●")
  of "open": warning("◆")
  of "closed": good("◇")
  else: mute("·")

proc badge*(text, kind: string): string =
  ## A short word in its colour, between brackets when there is no colour to set it apart.
  let code = case kind
    of "ok": Ok
    of "warn": Warn
    of "bad": Bad
    of "info": Info
    of "accent": Accent
    else: Mute
  if colorOn(): style(" " & text & " ", code & ";7") else: "[" & text & "]"

proc buildBadge*(status: string): string =
  case status
  of "succeeded": badge("built", "ok")
  of "failed", "errored": badge("failed", "bad")
  of "running", "pending", "queued": badge(status, "warn")
  of "", "none": ""
  else: badge(status, "mute")

# --- Shapes -----------------------------------------------------------------------------

proc heading*(title: string; sub = ""): string =
  accent("◆ ") & strong(title) & (if sub.len > 0: "  " & mute(sub) else: "")

proc rule*(width = 0): string =
  mute(repeat("─", if width > 0: width else: min(screenWidth(), 72)))

proc facts*(rows: openArray[(string, string)]): string =
  ## Labelled facts, labels in one muted column.
  var width = 0
  for (k, v) in rows:
    if v.len > 0:
      width = max(width, k.len)
  var lines: seq[string]
  for (k, v) in rows:
    if v.len > 0:
      lines.add("  " & mute(k.alignLeft(width)) & "  " & v)
  lines.join("\n")

proc bar*(done, total: int; width = 14): string =
  let filled = if total == 0: 0 else: (done * width) div total
  good(repeat("━", filled)) & mute(repeat("━", width - filled))

proc success*(msg: string) =
  echo good("✓ ") & msg

proc notice*(msg: string) =
  echo info("› ") & msg

proc caution*(msg: string) =
  stderr.writeLine(style("! ", Warn, stderr) & msg)

proc ago*(stamp: string): string =
  ## "3h ago" from an ISO time, the way the site says it.
  if stamp.len == 0:
    return ""
  var moment: DateTime
  try:
    moment = parse(stamp.replace("Z", "+00:00"), "yyyy-MM-dd'T'HH:mm:sszzz", utc())
  except CatchableError:
    return stamp
  let seconds = (now().utc - moment).inSeconds
  for (size, unit) in [(86400'i64 * 365, "y"), (86400'i64 * 30, "mo"), (
      86400'i64, "d"), (3600'i64, "h"), (60'i64, "m")]:
    if seconds >= size:
      return $(seconds div size) & unit & " ago"
  "just now"

proc dueNote*(due, state: string): string =
  ## Overdue, due today, soon: what a list should make you see.
  if due.len == 0 or state == "done":
    return ""
  var day: DateTime
  try:
    day = parse(due, "yyyy-MM-dd", utc())
  except CatchableError:
    return mute("due " & due)
  let today = parse(now().utc.format("yyyy-MM-dd"), "yyyy-MM-dd", utc())
  let days = (day - today).inDays
  if days < 0: bad("overdue " & $(-days) & "d")
  elif days == 0: warning("due today")
  elif days <= 3: warning("due in " & $days & "d")
  else: mute("due " & due)
