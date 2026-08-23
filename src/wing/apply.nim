## Plans and executes a template copy with placeholder substitution.

import std/[os, strutils]

import ./templates/manifest
import ./util

type
  TemplateApplyPlan* = object
    createDirs*: seq[string]
    copyFiles*: seq[string]
    symlinks*: seq[string]
    replacements*: seq[string]
    conflicts*: seq[string]
    rejectedSymlinks*: seq[string]
    skippedReplacements*: seq[string]
    skippedFiles*: seq[string]

proc childRel*(parent, child: string): string =
  if parent.len == 0: child else: parent / child

proc hasNul*(content: string): bool =
  for ch in content:
    if ch == '\0':
      return true

# Tokens a config added, ahead of the built-in ones so a config can replace what a built-in token
# would otherwise have already consumed. Set once before an apply rather than threaded through
# every proc that renders a path or a file.
var extraPlaceholders: seq[(string, string)]

proc setExtraPlaceholders*(pairs: seq[(string, string)]) =
  extraPlaceholders = pairs

# Asked for every file a template would write. Set once before an apply, for the same reason the
# placeholders are: threading it through every proc that walks a directory would touch all of them.
var fileFilter: proc (rel: string): bool {.closure.}

proc setFileFilter*(filter: proc (rel: string): bool {.closure.}) =
  fileFilter = filter

proc keepFile(rel: string): bool =
  # A template's manifest and its logic describe the template; they are not part of what it
  # produces. Excluded here rather than only where bundled templates are materialised, because an
  # installed template is applied straight out of its directory and never passes through that.
  if rel in [ManifestName, LogicName]:
    return false
  if fileFilter == nil: true else: fileFilter(rel)

proc pascalCase(value: string): string =
  ## `demo_thing` -> `DemoThing`. Languages whose identifiers must start with a capital -- a
  ## Haskell module, a C# class -- cannot use the raw project name, and lowercasing it is not the
  ## answer either.
  var atWordStart = true
  for ch in value:
    if ch in {'_', '-', ' ', '.'}:
      atWordStart = true
    elif atWordStart:
      result.add(ch.toUpperAscii())
      atWordStart = false
    else:
      result.add(ch)

proc capitalizeFirst(value: string): string =
  ## `demo_thing` -> `Demo_thing`. OCaml derives a module name from a filename by upper-casing the
  ## first letter and nothing else, so PascalCase is the wrong shape there.
  if value.len == 0:
    return ""
  result = value
  result[0] = result[0].toUpperAscii()

proc placeholderPairs*(projectName: string): seq[(string, string)] =
  let kebab = projectName.replace("_", "-")
  let kebabLower = kebab.toLowerAscii()
  let snake = projectName.replace("-", "_")
  let snakeLower = snake.toLowerAscii()
  extraPlaceholders & @[
    ("{{PROJECT_NAME}}", projectName),
    ("{{project_name}}", projectName),
    ("{{PROJECT-NAME}}", kebab),
    ("{{project-name}}", kebabLower),
    ("{{name}}", projectName),
    ("{{NAME}}", projectName.toUpperAscii()),
    ("{{kebab_name}}", kebabLower),
    ("{{snake_name}}", snakeLower),
    ("{{PascalName}}", pascalCase(projectName)),
    # OCaml derives a module name from a filename by upper-casing the first letter and nothing
    # else, so `demo_thing.ml` is module `Demo_thing`. PascalCase is the wrong shape there.
    ("{{Snake_name}}", capitalizeFirst(snakeLower))
  ]

proc inferProjectName*(targetPath: string): string =
  var cleaned = targetPath
  while cleaned.len > 1 and (cleaned[^1] == '/' or cleaned[^1] == '\\'):
    cleaned.setLen(cleaned.len - 1)
  let tail = splitPath(cleaned).tail
  if tail.len > 0:
    tail
  else:
    "project"

proc effectiveProjectName*(projectName, targetPath: string): string =
  if projectName.len > 0:
    return projectName
  if fileExists(targetPath) or dirExists(targetPath) or symlinkExists(
      targetPath):
    die("Target path '" & targetPath &
        "' already exists; pass --name PROJECT_NAME when applying a template to an existing path",
        2)
  inferProjectName(targetPath)

proc renderTemplateRel*(rel, projectName: string): string =
  result = rel
  if projectName.len == 0:
    return
  for pair in placeholderPairs(projectName):
    result = result.replace(pair[0], pair[1])

proc replacementStatus*(path, rel, projectName: string): tuple[needed: bool;
    skipped: string] =
  if projectName.len == 0:
    return (false, "")
  try:
    let content = readFile(path)
    if hasNul(content):
      return (false, rel & " (binary)")
    for pair in placeholderPairs(projectName):
      if content.contains(pair[0]):
        return (true, "")
  except CatchableError as e:
    return (false, rel & " (" & e.msg & ")")
  (false, "")

proc addConflictIfNeeded*(plan: var TemplateApplyPlan; target, rel: string) =
  if fileExists(target) or dirExists(target):
    plan.conflicts.add(rel)

proc addFileToPlan*(plan: var TemplateApplyPlan; srcPath, targetRoot, rel,
    projectName: string) =
  # A file a template's own logic declines is left out of the plan too, so a dry run shows what
  # would really be written rather than what the directory happens to hold.
  if not keepFile(rel):
    plan.skippedFiles.add(rel)
    return
  plan.copyFiles.add(rel)
  addConflictIfNeeded(plan, targetRoot / rel, rel)
  let status = replacementStatus(srcPath, rel, projectName)
  if status.needed:
    plan.replacements.add(rel)
  elif status.skipped.len > 0:
    plan.skippedReplacements.add(status.skipped)

proc addSymlinkToPlan*(plan: var TemplateApplyPlan; targetRoot, rel: string;
    allowSymlinks: bool) =
  if allowSymlinks:
    plan.symlinks.add(rel)
    addConflictIfNeeded(plan, targetRoot / rel, rel)
  else:
    plan.rejectedSymlinks.add(rel)

proc collectTemplateDir*(plan: var TemplateApplyPlan; srcRoot, targetRoot,
    relRoot, projectName: string; allowSymlinks: bool) =
  for kind, path in walkDir(srcRoot):
    let rawRel = childRel(relRoot, splitPath(path).tail)
    let rel = renderTemplateRel(rawRel, projectName)
    case kind
    of pcDir:
      plan.createDirs.add(rel)
      collectTemplateDir(plan, path, targetRoot, rawRel, projectName, allowSymlinks)
    of pcFile:
      addFileToPlan(plan, path, targetRoot, rel, projectName)
    of pcLinkToFile, pcLinkToDir:
      addSymlinkToPlan(plan, targetRoot, rel, allowSymlinks)

proc buildTemplatePlan*(srcPath, targetRoot, projectName: string;
    allowSymlinks: bool): TemplateApplyPlan =
  if dirExists(srcPath):
    collectTemplateDir(result, srcPath, targetRoot, "", projectName, allowSymlinks)
  elif fileExists(srcPath):
    addFileToPlan(result, srcPath, targetRoot,
        renderTemplateRel(splitPath(srcPath).tail, projectName), projectName)
  else:
    die("Template path '" & srcPath & "' does not exist")

proc printList*(title: string; items: seq[string]) =
  if items.len == 0:
    return
  echo title & ":"
  for item in items:
    echo "  " & item
  echo ""

proc printTemplatePlan*(templateName, targetPath, flavour: string;
    plan: TemplateApplyPlan) =
  echo "Template: " & templateName
  if flavour.len > 0:
    echo "Flavour: " & flavour
  echo "Target: " & targetPath
  echo ""
  printList("Create directories", plan.createDirs)
  printList("Copy files", plan.copyFiles)
  printList("Create symlinks", plan.symlinks)
  printList("Replace placeholders", plan.replacements)
  printList("Conflicts", plan.conflicts)
  printList("Rejected symlinks", plan.rejectedSymlinks)
  printList("Skipped placeholder replacements", plan.skippedReplacements)
  printList("Left out by the template's own logic", plan.skippedFiles)

proc replacePlaceholdersInFile*(path, rel, projectName: string;
    skipped: var seq[string]) =
  if projectName.len == 0:
    return
  try:
    var content = readFile(path)
    if hasNul(content):
      skipped.add(rel & " (binary)")
      return
    let original = content
    for pair in placeholderPairs(projectName):
      content = content.replace(pair[0], pair[1])
    if content != original:
      writeFile(path, content)
  except CatchableError as e:
    skipped.add(rel & " (" & e.msg & ")")

proc copyTemplateFile*(srcPath, targetPath, rel, projectName: string; force,
    skipExisting: bool; skippedReplacements: var seq[string]) =
  if not keepFile(rel):
    return
  if fileExists(targetPath) or dirExists(targetPath):
    if skipExisting:
      return
    if not force:
      die("Template target conflict: " & rel)
  createDir(parentDir(targetPath))
  copyFile(srcPath, targetPath)
  replacePlaceholdersInFile(targetPath, rel, projectName, skippedReplacements)

proc copyTemplateSymlink*(srcPath, targetPath, rel: string; force,
    skipExisting: bool) =
  if fileExists(targetPath) or dirExists(targetPath):
    if skipExisting:
      return
    if not force:
      die("Template target conflict: " & rel)
    removeFile(targetPath)
  createDir(parentDir(targetPath))
  createSymlink(expandSymlink(srcPath), targetPath)

proc applyTemplateDir*(srcRoot, targetRoot, relRoot, projectName: string; force,
    skipExisting, allowSymlinks: bool; skippedReplacements: var seq[string]) =
  createDir(targetRoot / renderTemplateRel(relRoot, projectName))
  for kind, path in walkDir(srcRoot):
    let rawRel = childRel(relRoot, splitPath(path).tail)
    let rel = renderTemplateRel(rawRel, projectName)
    let target = targetRoot / rel
    case kind
    of pcDir:
      applyTemplateDir(path, targetRoot, rawRel, projectName, force,
          skipExisting, allowSymlinks, skippedReplacements)
    of pcFile:
      copyTemplateFile(path, target, rel, projectName, force, skipExisting,
          skippedReplacements)
    of pcLinkToFile, pcLinkToDir:
      if not allowSymlinks:
        die("Template contains symlink '" & rel & "'; use --allow-symlinks")
      copyTemplateSymlink(path, target, rel, force, skipExisting)

proc applyTemplate*(srcPath, targetRoot, projectName: string; force,
    skipExisting, allowSymlinks: bool): seq[string] =
  if dirExists(srcPath):
    applyTemplateDir(srcPath, targetRoot, "", projectName, force, skipExisting,
        allowSymlinks, result)
  elif fileExists(srcPath):
    let rel = renderTemplateRel(splitPath(srcPath).tail, projectName)
    copyTemplateFile(srcPath, targetRoot / rel, rel, projectName, force,
        skipExisting, result)
  else:
    die("Template path '" & srcPath & "' does not exist")
