## Minimal TOML value encoding and decoding for the on-disk stores.

import std/[sequtils, strutils]

proc tomlEscape*(value: string): string =
  value
    .replace("\\", "\\\\")
    .replace("\"", "\\\"")
    .replace("\n", "\\n")

proc tomlString*(value: string): string =
  "\"" & tomlEscape(value) & "\""

proc unquoteToml*(value: string): string =
  var v = value.strip()
  if v.len >= 2 and v[0] == '"' and v[^1] == '"':
    if v.len == 2:
      return ""
    v = v.substr(1, v.len - 2)
    return v
      .replace("\\n", "\n")
      .replace("\\\"", "\"")
      .replace("\\\\", "\\")
  v

proc splitTomlArrayItems*(value: string): seq[string] =
  var current = ""
  var quoted = false
  var escaped = false
  for ch in value:
    if escaped:
      current.add(ch)
      escaped = false
    elif ch == '\\':
      current.add(ch)
      escaped = true
    elif ch == '"':
      current.add(ch)
      quoted = not quoted
    elif ch == ',' and not quoted:
      result.add(current.strip())
      current = ""
    else:
      current.add(ch)
  if current.strip().len > 0:
    result.add(current.strip())

proc parseStringArray*(value: string): seq[string] =
  let v = value.strip()
  if not (v.startsWith("[") and v.endsWith("]")):
    return @[]
  let inner =
    if v.len <= 2: ""
    else: v.substr(1, v.len - 2).strip()
  if inner.len == 0:
    return @[]
  for item in splitTomlArrayItems(inner):
    result.add(unquoteToml(item))

proc tomlArray*(values: seq[string]): string =
  "[" & values.mapIt(tomlString(it)).join(", ") & "]"

proc splitKeyValue*(line: string): tuple[key, value: string] =
  let idx = line.find('=')
  if idx < 0:
    return ("", "")
  (line[0 ..< idx].strip(), line[idx + 1 .. ^1].strip())
