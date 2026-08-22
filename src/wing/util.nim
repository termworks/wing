## Process exit, timestamps, and terminal formatting helpers.

import std/[os, strutils, terminal, times]

proc die*(message: string; code = 1) =
  stderr.writeLine(message)
  quit(code)

proc nowStamp*(): string =
  getTime().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")

proc displayStamp*(value: string): string =
  if value.len == 0:
    "unknown"
  else:
    value.replace("T", " ").replace("Z", " UTC")

proc dateOnly*(value: string): string =
  if value.len >= 10: value[0 .. 9] else: value

proc noneIfEmpty*(value: string): string =
  if value.len == 0: "None" else: value

proc unknownIfEmpty*(value: string): string =
  if value.len == 0: "unknown" else: value

proc colorHelp*(): bool =
  if getEnv("FORCE_COLOR").len > 0:
    return true
  if getEnv("NO_COLOR").len > 0 or getEnv("TERM") == "dumb":
    return false
  isatty(stdout)

proc paint*(value, code: string): string =
  if colorHelp(): "\e[" & code & "m" & value & "\e[0m" else: value

proc helpLine*(name, alias, description, code: string): string =
  let label =
    if alias.len > 0: name & " [" & alias & "]"
    else: name
  "  " & paint(label & repeat(" ", max(1, 18 - label.len)), code) &
      paint(description, "37")

proc table*(headers: seq[string]; rows: seq[seq[string]]): string =
  var widths = newSeq[int](headers.len)
  for i, header in headers:
    widths[i] = header.len
  for row in rows:
    for i, cell in row:
      if i < widths.len:
        widths[i] = max(widths[i], cell.len)

  proc renderRow(row: seq[string]): string =
    var cells: seq[string] = @[]
    for i in 0 ..< widths.len:
      let cell = if i < row.len: row[i] else: ""
      cells.add(cell & repeat(" ", widths[i] - cell.len))
    " " & cells.join("  ") & " "

  proc renderRule(): string =
    var cells: seq[string] = @[]
    for width in widths:
      cells.add(repeat("-", width))
    " " & cells.join("  ") & " "

  result.add(renderRow(headers))
  result.add("\n")
  result.add(renderRule())
  for row in rows:
    result.add("\n")
    result.add(renderRow(row))
