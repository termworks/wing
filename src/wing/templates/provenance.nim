## What generated this project, and what it looked like when it did.
##
## A template that is only ever applied once is a copy, not a template: the day a workflow is fixed
## or a recipe is added, every project already generated keeps the old one forever. This is the
## record that makes the other direction possible -- knowing which template made a project, and
## which of its files nobody has touched since, so an update can carry the ones that are safe and
## leave the ones that are not.
##
## Kept in the project rather than in wing's registry, because it has to travel with the project:
## cloned onto another machine, or handed to somebody else, it is still that template's project.

import std/[algorithm, md5, os, strutils]

import ../toml

const provenanceName* = ".wing.toml"

type
  Provenance* = object
    templateName*: string
    flavour*: string
    projectName*: string
    generatedAt*: string
    files*: seq[tuple[rel, hash: string]]

proc provenancePath*(root: string): string =
  root / provenanceName

proc hashContent*(content: string): string =
  getMD5(content)

proc hashFile*(path: string): string =
  if not fileExists(path):
    return ""
  hashContent(readFile(path))

proc findHash*(record: Provenance; rel: string): string =
  for entry in record.files:
    if entry.rel == rel:
      return entry.hash
  ""

proc projectFiles*(root: string): seq[string] =
  ## Every file under `root`, as paths relative to it, sorted.
  ##
  ## Not named `walkFiles`: `std/os` exports an *iterator* of that name that takes a glob, and in a
  ## `for` loop Nim picks the iterator over a proc of the same name -- so the loop silently globbed
  ## the directory path and yielded nothing, while the same call in an expression worked.
  ##
  ## `.git` is skipped: a repository's object store is not part of what a template generated, and
  ## walking it turns a comparison of thirty files into one of several thousand.
  for path in walkDirRec(root, relative = true):
    if path == provenanceName:
      continue
    let head = path.split(DirSep)[0]
    if head in [".git", ".direnv", "target", "build", "zig-out", "_build",
        "dist-newstyle", "node_modules"]:
      continue
    if fileExists(root / path):
      result.add(path)
  result.sort()

proc recordOf*(templateName, flavour, projectName, stamp,
    root: string): Provenance =
  ## What was just written, file by file.
  result = Provenance(templateName: templateName, flavour: flavour,
      projectName: projectName, generatedAt: stamp)
  for rel in projectFiles(root):
    result.files.add((rel: rel, hash: hashFile(root / rel)))

proc writeProvenance*(root: string; record: Provenance) =
  var text = "# Written by wing. It records which template generated this project and what each\n"
  text.add("# file looked like at the time, so `wing template update` can tell a file you edited\n")
  text.add("# from one the template changed. Commit it.\n\n")
  text.add("template = " & tomlString(record.templateName) & "\n")
  if record.flavour.len > 0:
    text.add("flavour = " & tomlString(record.flavour) & "\n")
  text.add("name = " & tomlString(record.projectName) & "\n")
  text.add("generated_at = " & tomlString(record.generatedAt) & "\n\n")
  for entry in record.files:
    text.add("[[files]]\n")
    text.add("path = " & tomlString(entry.rel) & "\n")
    text.add("hash = " & tomlString(entry.hash) & "\n\n")
  writeFile(provenancePath(root), text)

proc parseProvenance*(path: string): Provenance =
  if not fileExists(path):
    return
  var currentRel = ""
  var currentHash = ""
  var inFiles = false
  for rawLine in readFile(path).splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith("#"):
      continue
    if line == "[[files]]":
      if inFiles and currentRel.len > 0:
        result.files.add((rel: currentRel, hash: currentHash))
      inFiles = true
      currentRel = ""
      currentHash = ""
      continue
    if not line.contains("="):
      continue
    let (key, value) = splitKeyValue(line)
    if inFiles:
      case key
      of "path": currentRel = unquoteToml(value)
      of "hash": currentHash = unquoteToml(value)
      else: discard
    else:
      case key
      of "template": result.templateName = unquoteToml(value)
      of "flavour": result.flavour = unquoteToml(value)
      of "name": result.projectName = unquoteToml(value)
      of "generated_at": result.generatedAt = unquoteToml(value)
      else: discard
  if inFiles and currentRel.len > 0:
    result.files.add((rel: currentRel, hash: currentHash))

proc findProjectRoot*(start: string): string =
  ## The nearest directory at or above `start` that wing generated. Run from `src/` and it still
  ## finds the project, which is where anybody actually is when they think to run this.
  var dir = if start.len > 0: expandFilename(start) else: getCurrentDir()
  while true:
    if fileExists(provenancePath(dir)):
      return dir
    let parent = parentDir(dir)
    if parent == dir or parent.len == 0:
      return ""
    dir = parent
