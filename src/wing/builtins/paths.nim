## Locates the bundled template tree and its per-template subdirectories.

import std/os

import ../storage
import ../types
import ./flavours

proc userTemplatesRoot*(): string =
  ## `$XDG_CONFIG_HOME/wing/templates`, beside the user's init.lua.
  let xdg = getEnv("XDG_CONFIG_HOME")
  let base = if xdg.len > 0: xdg else: getHomeDir() / ".config"
  base / "wing" / "templates"

proc templateRoots*(): seq[string] =
  ## Every template tree, least specific first, so a later root overrides an earlier one by name.
  ##
  ## WING_TEMPLATE_DIR keeps its exclusive meaning: use only that tree. A build that has to be
  ## reproducible, and a test that has to see a known set, both want to name one directory and get
  ## exactly it.
  let fromEnv = getEnv("WING_TEMPLATE_DIR")
  if fromEnv.len > 0 and dirExists(fromEnv):
    return @[fromEnv]

  let appDir = parentDir(getAppFilename())
  let candidates = @[
    appDir / ".." / "share" / "wing" / "templates",
    appDir / "templates",
    # A checkout keeps everything that belongs in the config directory under `config/`, which is
      # what `make configs` installs; an installed tree has the templates directly beside the binary.
    getCurrentDir() / "config" / "templates",
    getCurrentDir() / "templates",
    dataRoot() / "templates",
    userTemplatesRoot()
  ]
  for candidate in candidates:
    if dirExists(candidate) and candidate notin result:
      result.add(candidate)

proc builtinTemplatePath*(tmpl: TemplateSpec): string =
  ## Where this template's own files are.
  ##
  ## An absolute `dir` is taken as written -- that is how a config points at a template outside
  ## every root. A manifest resolves against the root it was declared in. A user config has no
  ## root, so its relative `dir` is searched for across the roots, most specific first: that is
  ## what makes `wing.template("go", { description = "mine" })` override the description and still
  ## find the go files it did not mention.
  if isAbsolute(tmpl.dir):
    return tmpl.dir
  if tmpl.root.len > 0:
    return tmpl.root / tmpl.dir
  let roots = templateRoots()
  for i in countdown(roots.high, 0):
    let candidate = roots[i] / tmpl.dir
    if dirExists(candidate):
      return candidate
  tmpl.dir

proc builtinTemplateBasePath*(tmpl: TemplateSpec): string =
  let templatePath = builtinTemplatePath(tmpl)
  if builtinTemplateFlavours(tmpl).len > 0:
    templatePath / "base"
  else:
    templatePath

proc builtinTemplateFlavourPath*(tmpl: TemplateSpec; flavour: string): string =
  builtinTemplatePath(tmpl) / "flavours" / flavour

proc builtinCommonPath*(root: string): string =
  root / "common"

proc commonPaths*(): seq[string] =
  ## Every root's `common/`, in search order. Stacked before the template overlay, so overriding
  ## one shared file means dropping one file rather than copying the whole directory.
  for root in templateRoots():
    let path = builtinCommonPath(root)
    if dirExists(path):
      result.add(path)

proc builtinTemplateAvailable*(tmpl: TemplateSpec): bool =
  ## A common/ is shared extras, not a requirement: a template that only has its own files is
  ## usable, which is what a single-directory user template looks like.
  if not dirExists(builtinTemplateBasePath(tmpl)):
    return false
  for flavour in builtinTemplateFlavours(tmpl):
    if not dirExists(builtinTemplateFlavourPath(tmpl, flavour)):
      return false
  true
