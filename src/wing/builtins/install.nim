## Materializes bundled templates on disk and registers them in the store.

import std/[os, sequtils]

import ../jsonfmt
import ../storage
import ../store/templates
import ../types
import ../util
import ./flavours
import ./paths
import ../templates/manifest
import ./registry

proc copyBuiltinTemplateDir*(srcRoot, dstRoot, relRoot: string;
    tmpl: TemplateSpec; flavour: string) =
  for kind, path in walkDir(srcRoot):
    let rel = if relRoot.len == 0: splitPath(path).tail else: relRoot /
        splitPath(path).tail
    let dstPath = dstRoot / rel
    case kind
    of pcDir:
      createDir(dstPath)
      copyBuiltinTemplateDir(path, dstRoot, rel, tmpl, flavour)
    of pcFile:
      # The manifest describes the template; it is not part of what the template produces. Only at
      # the top level, so a template that legitimately generates a template.lua still can.
      if relRoot.len == 0 and splitPath(path).tail == ManifestName:
        continue
      createDir(parentDir(dstPath))
      writeFile(dstPath, renderBuiltinTemplate(readFile(path), tmpl, flavour))
    of pcLinkToFile, pcLinkToDir:
      discard

proc materializeBuiltinTemplate*(tmpl: TemplateSpec;
    requestedFlavour = ""): string =
  let flavour = normalizeBuiltinFlavour(tmpl, requestedFlavour)
  let overlayPath = builtinTemplateBasePath(tmpl)
  if not dirExists(overlayPath):
    die("Template path '" & overlayPath & "' does not exist", 2)
  if flavour.len > 0:
    let flavourPath = builtinTemplateFlavourPath(tmpl, flavour)
    if not dirExists(flavourPath):
      die("Template flavour path '" & flavourPath & "' does not exist", 2)

  let outputName =
    if flavour.len > 0 and flavour != tmpl.defaultFlavour:
      tmpl.name & "-" & flavour
    else:
      tmpl.name
  result = dataRoot() / "builtin-templates" / outputName
  if dirExists(result):
    removeDir(result)
  createDir(result)
  # common/ from every root, least specific first, then this template, then its flavour. Each layer
  # overwrites the one before, which is how one file in a user common/ replaces one bundled file.
  for common in commonPaths():
    copyBuiltinTemplateDir(common, result, "", tmpl, flavour)
  copyBuiltinTemplateDir(overlayPath, result, "", tmpl, flavour)
  if flavour.len > 0:
    copyBuiltinTemplateDir(builtinTemplateFlavourPath(tmpl, flavour),
        result, "", tmpl, flavour)

proc printBuiltinTemplates*(raw, asJson: bool) =
  if asJson:
    echo "["
    let specs = builtinSpecs()
    for i, tmpl in specs:
      let path = builtinTemplatePath(tmpl)
      let suffix = if i == specs.high: "" else: ","
      echo "  {\"name\": " & jsonString(tmpl.name) &
          ", \"description\": " & jsonString(tmpl.description) &
          ", \"path\": " & jsonString(path) &
          ", \"language\": " & jsonString(tmpl.language) &
          ", \"framework\": " & jsonString(tmpl.framework) &
          ", \"flavours\": " & jsonStringArray(builtinTemplateFlavours(tmpl)) &
          ", \"default_flavour\": " & jsonString(tmpl.defaultFlavour) &
          ", \"available\": " & (if builtinTemplateAvailable(
              tmpl): "true" else: "false") &
          "}" & suffix
    echo "]"
  elif raw:
    for tmpl in builtinSpecs():
      let path = builtinTemplatePath(tmpl)
      echo tmpl.name & "\t" & tmpl.language & "\t" & path
  else:
    echo table(
      @["Name", "Description", "Language", "Flavours", "Path", "Status"],
      builtinSpecs().mapIt(@[
        it.name,
        it.description,
        it.language,
        builtinFlavourSummary(it),
        builtinTemplatePath(it),
        if builtinTemplateAvailable(it): "ready" else: "missing"
      ])
    )

proc installBuiltinTemplates*(path: string; templates: var seq[Template];
    force: bool) =
  if templateRoots().len == 0:
    die("No templates found. Set WING_TEMPLATE_DIR, or put a tree in " &
        userTemplatesRoot(), 2)

  var added = 0
  var updated = 0
  var skipped = 0
  templates = templates.filterIt(not @["go-cli", "zig-cli", "nim-cli"].contains(
      it.name))
  for builtin in builtinSpecs():
    let templatePath = materializeBuiltinTemplate(builtin)

    var found = -1
    for i, tmpl in templates:
      if tmpl.name == builtin.name:
        found = i
        break

    let stamp = nowStamp()
    let record = Template(
      name: builtin.name,
      description: builtin.description,
      path: templatePath,
      language: builtin.language,
      framework: builtin.framework,
      tags: builtinTemplateTags(builtin),
      createdAt: stamp,
      updatedAt: stamp
    )
    if found >= 0:
      if force:
        templates[found].description = record.description
        templates[found].path = record.path
        templates[found].language = record.language
        templates[found].framework = record.framework
        templates[found].tags = record.tags
        templates[found].updatedAt = stamp
        inc updated
      else:
        inc skipped
    else:
      templates.add(record)
      inc added

  writeTemplates(path, templates)
  echo "Bundled templates installed: " & $added & " added, " & $updated &
      " updated, " & $skipped & " skipped"

proc findBuiltinTemplate*(name: string): int =
  findBuiltinSpec(name)

proc templateBuiltinIndex*(tmpl: Template): int =
  if not tmpl.tags.contains("builtin"):
    return -1
  findBuiltinTemplate(tmpl.name)

proc templateSourceForFlavour*(tmpl: Template; requested: string;
    hasRequested: bool): tuple[path: string; flavour: string] =
  result.path = tmpl.path
  let index = templateBuiltinIndex(tmpl)
  if index < 0:
    if hasRequested:
      die("Template '" & tmpl.name & "' does not support flavours", 2)
    return

  let builtin = builtinSpecs()[index]
  let flavours = builtinTemplateFlavours(builtin)
  if flavours.len == 0:
    if hasRequested:
      die("Template '" & tmpl.name & "' does not support flavours", 2)
    return

  result.flavour = normalizeBuiltinFlavour(builtin, requested)
  if not hasRequested:
    return

  result.path = materializeBuiltinTemplate(builtin, result.flavour)
