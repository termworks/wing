## projects.toml parsing and serialization.

import std/strutils

import ../storage
import ../toml
import ../types
import ../util

proc parseProjects*(path: string): seq[Project] =
  let content = readConfig(path)
  var current = -1
  for rawLine in content.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith("#"):
      continue
    if line == "[[projects]]":
      let stamp = nowStamp()
      result.add(Project(namespace: "default", tags: @[], createdAt: stamp,
          updatedAt: stamp))
      current = result.high
    elif current >= 0 and line.contains("="):
      let (key, value) = splitKeyValue(line)
      case key
      of "name": result[current].name = unquoteToml(value)
      of "path": result[current].path = unquoteToml(value)
      of "namespace": result[current].namespace = unquoteToml(value)
      of "template", "templateName": result[current].templateName = unquoteToml(value)
      of "description": result[current].description = unquoteToml(value)
      of "language": result[current].language = unquoteToml(value)
      of "framework": result[current].framework = unquoteToml(value)
      of "tags": result[current].tags = parseStringArray(value)
      of "machine": result[current].machine = unquoteToml(value)
      of "created_at", "createdAt": result[current].createdAt = unquoteToml(value)
      of "updated_at", "updatedAt": result[current].updatedAt = unquoteToml(value)
      else: discard

proc writeProjects*(path: string; projects: seq[Project]) =
  var text = schemaHeader()
  if projects.len == 0:
    text.add("projects = []\n")
  else:
    for project in projects:
      text.add("[[projects]]\n")
      text.add("name = " & tomlString(project.name) & "\n")
      text.add("path = " & tomlString(project.path) & "\n")
      text.add("namespace = " & tomlString(project.namespace) & "\n")
      if project.templateName.len > 0: text.add("template = " & tomlString(
          project.templateName) & "\n")
      if project.description.len > 0: text.add("description = " & tomlString(
          project.description) & "\n")
      if project.language.len > 0: text.add("language = " & tomlString(
          project.language) & "\n")
      if project.framework.len > 0: text.add("framework = " & tomlString(
          project.framework) & "\n")
      text.add("tags = " & tomlArray(project.tags) & "\n")
      if project.machine.len > 0:
        text.add("machine = " & tomlString(project.machine) & "\n")
      text.add("created_at = " & tomlString(project.createdAt) & "\n")
      text.add("updated_at = " & tomlString(project.updatedAt) & "\n\n")
  atomicWriteFile(path, text)

proc ensureProjectsFile*(): string =
  result = configPath("projects.toml")
  ensureFile(result, schemaHeader() & "projects = []\n")
