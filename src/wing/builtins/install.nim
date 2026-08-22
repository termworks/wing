## Materializes bundled templates on disk and registers them in the store.

import std/[os, sequtils]

import ../embedded
import ../jsonfmt
import ../storage
import ../store/templates
import ../types
import ../util
import ./data
import ./flavours
import ./paths

proc copyBuiltinTemplateDir*(srcRoot, dstRoot, relRoot: string;
    tmpl: BuiltinTemplate; flavour: string) =
  for kind, path in walkDir(srcRoot):
    let rel = if relRoot.len == 0: splitPath(path).tail else: relRoot /
        splitPath(path).tail
    let dstPath = dstRoot / rel
    case kind
    of pcDir:
      createDir(dstPath)
      copyBuiltinTemplateDir(path, dstRoot, rel, tmpl, flavour)
    of pcFile:
      createDir(parentDir(dstPath))
      writeFile(dstPath, renderBuiltinTemplate(readFile(path), tmpl, flavour))
    of pcLinkToFile, pcLinkToDir:
      discard

proc materializeBuiltinTemplate*(root: string; tmpl: BuiltinTemplate;
    requestedFlavour = ""): string =
  let flavour = normalizeBuiltinFlavour(tmpl, requestedFlavour)
  let commonPath = builtinCommonPath(root)
  let overlayPath = builtinTemplateBasePath(root, tmpl)
  if not dirExists(commonPath):
    die("Bundled template common path '" & commonPath & "' does not exist", 2)
  if not dirExists(overlayPath):
    die("Bundled template path '" & overlayPath & "' does not exist", 2)
  if flavour.len > 0:
    let flavourPath = builtinTemplateFlavourPath(root, tmpl, flavour)
    if not dirExists(flavourPath):
      die("Bundled template flavour path '" & flavourPath &
          "' does not exist", 2)

  let outputName =
    if flavour.len > 0 and flavour != tmpl.defaultFlavour:
      tmpl.name & "-" & flavour
    else:
      tmpl.name
  result = dataRoot() / "builtin-templates" / outputName
  if dirExists(result):
    removeDir(result)
  createDir(result)
  copyBuiltinTemplateDir(commonPath, result, "", tmpl, flavour)
  copyBuiltinTemplateDir(overlayPath, result, "", tmpl, flavour)
  if flavour.len > 0:
    copyBuiltinTemplateDir(builtinTemplateFlavourPath(root, tmpl, flavour),
        result, "", tmpl, flavour)

proc printBuiltinTemplates*(root: string; raw, asJson: bool) =
  if asJson:
    echo "["
    for i, tmpl in BuiltinTemplates:
      let path = if root.len > 0: builtinTemplatePath(root, tmpl) else: ""
      let suffix = if i == BuiltinTemplates.high: "" else: ","
      echo "  {\"name\": " & jsonString(tmpl.name) &
          ", \"description\": " & jsonString(tmpl.description) &
          ", \"path\": " & jsonString(path) &
          ", \"language\": " & jsonString(tmpl.language) &
          ", \"framework\": " & jsonString(tmpl.framework) &
          ", \"flavours\": " & jsonStringArray(builtinTemplateFlavours(tmpl)) &
          ", \"default_flavour\": " & jsonString(tmpl.defaultFlavour) &
          ", \"available\": " & (if builtinTemplateAvailable(root,
              tmpl): "true" else: "false") &
          "}" & suffix
    echo "]"
  elif raw:
    for tmpl in BuiltinTemplates:
      let path = if root.len > 0: builtinTemplatePath(root, tmpl) else: ""
      echo tmpl.name & "\t" & tmpl.language & "\t" & path
  else:
    echo table(
      @["Name", "Description", "Language", "Flavours", "Path", "Status"],
      BuiltinTemplates.mapIt(@[
        it.name,
        it.description,
        it.language,
        builtinFlavourSummary(it),
        if root.len > 0: builtinTemplatePath(root, it) else: "None",
        if builtinTemplateAvailable(root, it): "ready" else: "missing"
      ])
    )

proc installBuiltinTemplates*(path: string; templates: var seq[Template];
    force: bool; sourceRoot = "") =
  if sourceRoot.len == 0 and getEnv("WING_TEMPLATE_DIR").len == 0:
    discard ensureEmbeddedTemplateSources(false)
  let root = if sourceRoot.len > 0: sourceRoot else: builtinTemplatesRoot()
  if root.len == 0:
    die("Bundled templates not found. Set WING_TEMPLATE_DIR or run wing init", 2)

  var added = 0
  var updated = 0
  var skipped = 0
  templates = templates.filterIt(not @["go-cli", "zig-cli", "nim-cli"].contains(
      it.name))
  for builtin in BuiltinTemplates:
    let templatePath = materializeBuiltinTemplate(root, builtin)

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
  result = -1
  for i, builtin in BuiltinTemplates:
    if builtin.name == name:
      return i

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

  let builtin = BuiltinTemplates[index]
  let flavours = builtinTemplateFlavours(builtin)
  if flavours.len == 0:
    if hasRequested:
      die("Template '" & tmpl.name & "' does not support flavours", 2)
    return

  result.flavour = normalizeBuiltinFlavour(builtin, requested)
  if not hasRequested:
    return

  if getEnv("WING_TEMPLATE_DIR").len == 0:
    discard ensureEmbeddedTemplateSources(false)
  let root = builtinTemplatesRoot()
  if root.len == 0:
    die("Bundled templates not found. Set WING_TEMPLATE_DIR or run wing init",
        2)
  result.path = materializeBuiltinTemplate(root, builtin, result.flavour)
