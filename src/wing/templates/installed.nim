## The record of installed templates: where each came from, and what it hashed to.
##
## Kept beside the templates themselves rather than in the project registry (`templates.toml`),
## because this answers a different question. `templates.toml` says which templates exist and where
## their files are; this says which ones arrived from somewhere else and whether their code has
## changed since you agreed to it.

import std/[os, strutils]

import ../storage
import ../toml
import ./source

type
  InstalledTemplate* = object
    name*: string
    source*: string
    revision*: string
    hash*: string
    installedAt*: string

  TrustState* = enum
    tsUnmanaged ## not installed by wing; nothing to check
    tsOk        ## the code hashes to what was agreed
    tsChanged   ## the code changed since it was agreed

proc installedRoot*(): string =
  ## Where installed templates live. The highest-priority root already, so an installed template
  ## overrides a bundled one of the same name.
  dataRoot() / "templates"

proc installedFile*(): string =
  configPath("installed.toml")

proc parseInstalled*(path: string): seq[InstalledTemplate] =
  let content = readConfig(path)
  var current = -1
  for rawLine in content.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith("#"):
      continue
    if line == "[[installed]]":
      result.add(InstalledTemplate())
      current = result.high
    elif current >= 0 and line.contains("="):
      let (key, value) = splitKeyValue(line)
      case key
      of "name": result[current].name = unquoteToml(value)
      of "source": result[current].source = unquoteToml(value)
      of "revision": result[current].revision = unquoteToml(value)
      of "hash": result[current].hash = unquoteToml(value)
      of "installed_at": result[current].installedAt = unquoteToml(value)
      else: discard

proc writeInstalled*(path: string; entries: seq[InstalledTemplate]) =
  var text = schemaHeader()
  if entries.len == 0:
    text.add("installed = []\n")
  else:
    for entry in entries:
      text.add("[[installed]]\n")
      text.add("name = " & tomlString(entry.name) & "\n")
      text.add("source = " & tomlString(entry.source) & "\n")
      if entry.revision.len > 0:
        text.add("revision = " & tomlString(entry.revision) & "\n")
      text.add("hash = " & tomlString(entry.hash) & "\n")
      text.add("installed_at = " & tomlString(entry.installedAt) & "\n\n")
  atomicWriteFile(path, text)

proc ensureInstalledFile*(): string =
  result = installedFile()
  ensureFile(result, schemaHeader() & "installed = []\n")

proc findInstalled*(entries: seq[InstalledTemplate]; name: string): int =
  result = -1
  for i, entry in entries:
    if entry.name == name:
      return i

proc trustOf*(entries: seq[InstalledTemplate]; name, dir: string): TrustState =
  ## Whether the code on disk still hashes to what was agreed at install.
  ##
  ## A template wing did not install is unmanaged, not untrusted: the bundled tree and anything the
  ## user wrote by hand are theirs already, and gating those would be a refusal with no remedy.
  let idx = findInstalled(entries, name)
  if idx < 0:
    return tsUnmanaged
  if not dirExists(dir):
    return tsChanged
  if hashTemplate(dir) == entries[idx].hash: tsOk else: tsChanged
