## syncs.toml parsing and serialization.

import std/strutils

import ../storage
import ../toml
import ../types

proc parseSyncs*(path: string): seq[SyncTarget] =
  let content = readConfig(path)
  var current = -1
  for rawLine in content.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith("#"):
      continue
    if line == "[[syncs]]":
      result.add(SyncTarget(direction: "push", exclude: @[]))
      current = result.high
    elif current >= 0 and line.contains("="):
      let (key, value) = splitKeyValue(line)
      case key
      of "name":
        result[current].name = unquoteToml(value)
      of "project":
        result[current].project = unquoteToml(value)
      of "machine":
        result[current].machine = unquoteToml(value)
      of "interface", "iface":
        result[current].iface = unquoteToml(value)
      of "remote_path", "remotePath":
        result[current].remotePath = unquoteToml(value)
      of "direction":
        result[current].direction = unquoteToml(value)
      of "delete":
        result[current].delete = value.strip() == "true"
      of "exclude":
        result[current].exclude = parseStringArray(value)
      of "created_at", "createdAt":
        result[current].createdAt = unquoteToml(value)
      of "updated_at", "updatedAt":
        result[current].updatedAt = unquoteToml(value)
      else:
        discard

proc writeSyncs*(path: string; syncs: seq[SyncTarget]) =
  var text = schemaHeader()
  if syncs.len == 0:
    text.add("syncs = []\n")
  else:
    for s in syncs:
      text.add("[[syncs]]\n")
      text.add("name = " & tomlString(s.name) & "\n")
      text.add("project = " & tomlString(s.project) & "\n")
      text.add("machine = " & tomlString(s.machine) & "\n")
      if s.iface.len > 0:
        text.add("interface = " & tomlString(s.iface) & "\n")
      text.add("remote_path = " & tomlString(s.remotePath) & "\n")
      text.add("direction = " & tomlString(s.direction) & "\n")
      text.add("delete = " & (if s.delete: "true" else: "false") & "\n")
      text.add("exclude = " & tomlArray(s.exclude) & "\n")
      text.add("created_at = " & tomlString(s.createdAt) & "\n")
      text.add("updated_at = " & tomlString(s.updatedAt) & "\n\n")
  atomicWriteFile(path, text)

proc ensureSyncsFile*(): string =
  result = configPath("syncs.toml")
  ensureFile(result, schemaHeader() & "syncs = []\n")

proc findSync*(syncs: seq[SyncTarget]; name: string): int =
  result = -1
  for i, s in syncs:
    if s.name == name:
      return i
