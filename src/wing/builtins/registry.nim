## The available templates, as declared by their own manifests, and the Lua state they came from.
##
## This replaces the compiled-in `BuiltinTemplates` array. The config is read once per process:
## every listing, apply and install in one command sees the same set, and the state stays open
## because placeholders and apply handlers are Lua functions called later, during an apply.

import ../lua/vm
import ../templates/manifest
import ../types
import ../util
import ./paths

var
  configVm: LuaVm
  cached: seq[TemplateSpec]
  loaded = false

proc ensureLoaded() =
  if not loaded:
    # A config that cannot be read is fatal, and reported as Lua wrote it -- file and line. The
    # alternative is a template silently missing from the listing, which reads as "wing lost my
    # template" rather than "line 4 of this file has a typo".
    try:
      configVm = openConfig(builtinTemplatesRoot(), userConfigPath())
    except LuaError as err:
      die("wing config: " & err.msg)
    cached = readSpecs(configVm.L)
    loaded = true

proc builtinSpecs*(): seq[TemplateSpec] =
  ensureLoaded()
  cached

proc findBuiltinSpec*(name: string): int =
  ## Index into `builtinSpecs()`, or -1.
  result = -1
  let specs = builtinSpecs()
  for i, spec in specs:
    if spec.name == name:
      return i

proc configPlaceholders*(ctx: openArray[(string, string)]): seq[(string, string)] =
  ensureLoaded()
  placeholderOverrides(configVm.L, ctx)

proc runConfigApplyHandlers*(ctx: openArray[(string, string)]) =
  ensureLoaded()
  runApplyHandlers(configVm.L, ctx)
