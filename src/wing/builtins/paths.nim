## Locates the bundled template tree and its per-template subdirectories.

import std/os

import ../storage
import ../types
import ./flavours

proc builtinTemplatesRoot*(): string =
  let fromEnv = getEnv("WING_TEMPLATE_DIR")
  if fromEnv.len > 0 and dirExists(fromEnv):
    return fromEnv

  let appDir = parentDir(getAppFilename())
  let candidates = @[
    dataRoot() / "templates",
    getCurrentDir() / "templates",
    appDir / "templates",
    appDir / ".." / "share" / "wing" / "templates"
  ]
  for candidate in candidates:
    if dirExists(candidate):
      return candidate
  ""

proc builtinTemplatePath*(root: string; tmpl: TemplateSpec): string =
  root / tmpl.dir

proc builtinTemplateBasePath*(root: string; tmpl: TemplateSpec): string =
  let templatePath = builtinTemplatePath(root, tmpl)
  if builtinTemplateFlavours(tmpl).len > 0:
    templatePath / "base"
  else:
    templatePath

proc builtinTemplateFlavourPath*(root: string; tmpl: TemplateSpec;
    flavour: string): string =
  builtinTemplatePath(root, tmpl) / "flavours" / flavour

proc builtinCommonPath*(root: string): string =
  root / "common"

proc builtinTemplateAvailable*(root: string; tmpl: TemplateSpec): bool =
  if root.len == 0 or not dirExists(builtinCommonPath(root)) or not dirExists(
      builtinTemplateBasePath(root, tmpl)):
    return false
  for flavour in builtinTemplateFlavours(tmpl):
    if not dirExists(builtinTemplateFlavourPath(root, tmpl, flavour)):
      return false
  true
