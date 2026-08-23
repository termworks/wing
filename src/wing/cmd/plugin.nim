## `wing template install / installed / remove-installed / allow` — templates as things you fetch.
##
## The shape is oslo's plugin model: a source is a path or a git repository at a pinned revision,
## what it declares is shown before it is kept, and its code is hashed so a later change has to be
## agreed to rather than picked up silently.

import std/[os, sequtils, strutils]

import ../cliargs
import ../store/templates
import ../types
import ../templates/install
import ../templates/manifest
import ../templates/installed
import ../templates/source
import ../util

proc showRow(name, detail: string) =
  echo "  " & name & repeat(" ", max(1, 14 - name.len)) & detail

proc describeCandidate(candidate: Candidate; src: Source) =
  echo "Source:   " & describe(src)
  echo "Hash:     " & candidate.hash
  echo "Declares:"
  for spec in candidate.specs:
    var detail = spec.description
    if spec.flavours.len > 0:
      var names: seq[string]
      for flavour in spec.flavours:
        names.add(flavour.name)
      detail.add("  [" & names.join(", ") & "]")
    showRow(spec.name, detail)
  if candidate.hasLogic:
    echo "Logic:    " & LogicName & " — this template runs code of its own when applied"

proc registerInstalled(specs: seq[TemplateSpec]; root, stamp: string) =
  ## Put the installed templates in the registry, so `wing template apply` finds them straight
  ## away. Installing something and then being told it does not exist is not an install.
  let path = ensureTemplatesFile()
  var registry = parseTemplates(path)
  for spec in specs:
    let record = Template(
      name: spec.name,
      description: spec.description,
      path: root / spec.name,
      language: spec.language,
      framework: spec.framework,
      tags: spec.tags,
      createdAt: stamp,
      updatedAt: stamp
    )
    var found = -1
    for i, existing in registry:
      if existing.name == spec.name:
        found = i
        break
    if found >= 0: registry[found] = record else: registry.add(record)
  writeTemplates(path, registry)

proc handleInstall*(argsIn: seq[string]) =
  var args = argsIn
  let assumeYes = popFlag(args, ["-y", "--yes"])
  rejectUnknownOptions(args)
  requireArgs(args, 1, "wing template install <path | github:user/repo@rev> [--yes]")

  var src: Source
  try:
    src = parseSource(args[0])
  except SourceError as err:
    die(err.msg, 2)

  let staging = getTempDir() / "wing-install-" & $getCurrentProcessId()
  removeDir(staging)
  createDir(staging)
  defer: removeDir(staging)

  let fetched = fetch(src, staging)
  let candidate = inspect(fetched)

  # Shown before anything lands. The manifest was read without the template's own logic, so this is
  # a claim about what it is rather than the result of running it.
  describeCandidate(candidate, src)

  var entries = parseInstalled(ensureInstalledFile())
  for spec in candidate.specs:
    let existing = findInstalled(entries, spec.name)
    if existing >= 0 and not assumeYes:
      die("Template '" & spec.name &
          "' is already installed. Pass --yes to replace it.", 2)

  if not assumeYes:
    stdout.write("Install? [y/N] ")
    stdout.flushFile()
    let answer = try: stdin.readLine() except EOFError: ""
    if answer.strip().toLowerAscii() notin ["y", "yes"]:
      echo "Nothing was installed."
      return

  let root = installedRoot()
  createDir(root)
  # Every template a manifest declared gets its own directory, so removing one is removing a
  # directory and a row rather than unpicking a shared tree.
  let stamp = nowStamp()
  for spec in candidate.specs:
    let dest = root / spec.name
    copyInto(candidate, dest)
    let record = InstalledTemplate(
      name: spec.name,
      source: describe(src),
      revision: (if src.kind == skGit: src.revision else: ""),
      hash: hashTemplate(dest),
      installedAt: stamp
    )
    let existing = findInstalled(entries, spec.name)
    if existing >= 0: entries[existing] = record else: entries.add(record)
    echo "Installed '" & spec.name & "' -> " & dest

  writeInstalled(installedFile(), entries)
  registerInstalled(candidate.specs, root, stamp)

proc handleInstalled*(argsIn: seq[string]) =
  var args = argsIn
  rejectUnknownOptions(args)
  let entries = parseInstalled(ensureInstalledFile())
  if entries.len == 0:
    echo "No installed templates. Add one with: wing template install <source>"
    return
  for entry in entries:
    let dir = installedRoot() / entry.name
    let state = trustOf(entries, entry.name, dir)
    let mark =
      case state
      of tsOk: "ok"
      of tsChanged: "CHANGED — run `wing template allow " & entry.name & "`"
      of tsUnmanaged: "missing"
    showRow(entry.name, entry.source & "  " & mark)

proc handleAllow*(argsIn: seq[string]) =
  var args = argsIn
  rejectUnknownOptions(args)
  requireArgs(args, 1, "wing template allow NAME")
  let name = args[0]
  var entries = parseInstalled(ensureInstalledFile())
  let idx = findInstalled(entries, name)
  if idx < 0:
    die("Template '" & name & "' was not installed by wing", 2)
  let dir = installedRoot() / name
  if not dirExists(dir):
    die("Template '" & name & "' is recorded but its files are gone", 2)
  entries[idx].hash = hashTemplate(dir)
  writeInstalled(installedFile(), entries)
  echo "Allowed '" & name & "' at its current contents"

proc handleRemoveInstalled*(argsIn: seq[string]) =
  var args = argsIn
  rejectUnknownOptions(args)
  requireArgs(args, 1, "wing template uninstall NAME")
  let name = args[0]
  var entries = parseInstalled(ensureInstalledFile())
  let idx = findInstalled(entries, name)
  if idx < 0:
    die("Template '" & name & "' was not installed by wing", 2)
  removeDir(installedRoot() / name)
  entries.delete(idx)
  writeInstalled(installedFile(), entries)

  # Out of the registry as well, so `apply` does not point at a directory that is gone.
  let path = ensureTemplatesFile()
  var registry = parseTemplates(path)
  let before = registry.len
  registry = registry.filterIt(it.name != name)
  if registry.len != before:
    writeTemplates(path, registry)
  echo "Uninstalled '" & name & "'"
