## Filesystem scan that recognizes projects by their build manifests.

import std/[os, sequtils, strutils]

import ./jsonfmt
import ./util

type
  DetectedProject* = object
    name*: string
    path*: string
    language*: string
    framework*: string

proc hasNimbleFile*(path: string): bool =
  for kind, item in walkDir(path):
    if kind == pcFile and item.endsWith(".nimble"):
      return true

proc detectProject*(path: string): tuple[found: bool;
    project: DetectedProject] =
  var language = ""
  var hints: seq[string] = @[]

  if dirExists(path / ".git") or fileExists(path / ".git"):
    hints.add("git")
  if fileExists(path / "go.mod"):
    language = "Go"
    hints.add("go modules")
  if fileExists(path / "Cargo.toml"):
    if language.len == 0:
      language = "Rust"
    hints.add("cargo")
  if hasNimbleFile(path):
    if language.len == 0:
      language = "Nim"
    hints.add("nimble")
  if fileExists(path / "pyproject.toml") or fileExists(path / "setup.py"):
    if language.len == 0:
      language = "Python"
    hints.add("python")
  if fileExists(path / "package.json"):
    if language.len == 0:
      language = "Node"
    hints.add("npm")
  if fileExists(path / "build.zig"):
    if language.len == 0:
      language = "Zig"
    hints.add("zig")

  if hints.len == 0:
    return (false, DetectedProject())

  let normalized = normalizedPath(path)
  (true, DetectedProject(
    name: splitPath(normalized).tail,
    path: normalized,
    language: language,
    framework: hints.join(", ")
  ))

proc ignoredDiscoveryDir*(path: string): bool =
  splitPath(path).tail in [".git", "node_modules", "target", "nimcache",
      ".direnv", "vendor", "result"]

proc discoverProjects*(root: string; maxDepth: int): seq[DetectedProject] =
  var foundProjects: seq[DetectedProject] = @[]

  proc scan(path: string; depth: int) =
    if depth > maxDepth or (depth > 0 and ignoredDiscoveryDir(path)):
      return
    let detected = detectProject(path)
    if detected.found:
      foundProjects.add(detected.project)
    if depth == maxDepth:
      return
    for kind, child in walkDir(path):
      if kind == pcDir:
        scan(child, depth + 1)

  if not dirExists(root):
    die("Discovery path '" & root & "' does not exist")
  scan(root, 0)
  result = foundProjects

proc printDiscovered*(projects: seq[DetectedProject]; asJson: bool) =
  if asJson:
    echo "["
    for i, project in projects:
      let suffix = if i == projects.high: "" else: ","
      echo "  {\"name\": " & jsonString(project.name) & ", \"path\": " &
          jsonString(project.path) & ", \"language\": " &
          jsonString(project.language) & ", \"framework\": " &
          jsonString(project.framework) & "}" & suffix
    echo "]"
  elif projects.len == 0:
    echo "No projects discovered"
  else:
    echo table(
      @["Name", "Path", "Language", "Framework"],
      projects.mapIt(@[
        it.name,
        it.path,
        noneIfEmpty(it.language),
        noneIfEmpty(it.framework)
      ])
    )
