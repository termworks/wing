## templates.toml parsing and serialization.

import std/strutils

import ../storage
import ../toml
import ../types
import ../util

proc parseTemplates*(path: string): seq[Template] =
  let content = readConfig(path)
  var current = -1
  for rawLine in content.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith("#"):
      continue
    if line == "[[templates]]":
      let stamp = nowStamp()
      result.add(Template(tags: @[], createdAt: stamp, updatedAt: stamp))
      current = result.high
    elif current >= 0 and line.contains("="):
      let (key, value) = splitKeyValue(line)
      case key
      of "name": result[current].name = unquoteToml(value)
      of "description": result[current].description = unquoteToml(value)
      of "path": result[current].path = unquoteToml(value)
      of "language": result[current].language = unquoteToml(value)
      of "framework": result[current].framework = unquoteToml(value)
      of "tags": result[current].tags = parseStringArray(value)
      of "created_at", "createdAt": result[current].createdAt = unquoteToml(value)
      of "updated_at", "updatedAt": result[current].updatedAt = unquoteToml(value)
      else: discard

proc writeTemplates*(path: string; templates: seq[Template]) =
  var text = schemaHeader()
  if templates.len == 0:
    text.add("templates = []\n")
  else:
    for tmpl in templates:
      text.add("[[templates]]\n")
      text.add("name = " & tomlString(tmpl.name) & "\n")
      text.add("description = " & tomlString(tmpl.description) & "\n")
      text.add("path = " & tomlString(tmpl.path) & "\n")
      if tmpl.language.len > 0: text.add("language = " & tomlString(
          tmpl.language) & "\n")
      if tmpl.framework.len > 0: text.add("framework = " & tomlString(
          tmpl.framework) & "\n")
      text.add("tags = " & tomlArray(tmpl.tags) & "\n")
      text.add("created_at = " & tomlString(tmpl.createdAt) & "\n")
      text.add("updated_at = " & tomlString(tmpl.updatedAt) & "\n\n")
  atomicWriteFile(path, text)

proc ensureTemplatesFile*(): string =
  result = configPath("templates.toml")
  ensureFile(result, schemaHeader() & "templates = []\n")
