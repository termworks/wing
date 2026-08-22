## The available templates, as declared by their own manifests.
##
## This replaces the compiled-in `BuiltinTemplates` array. The specs are read once per process:
## every listing, apply and install in one command sees the same set, and a config is not run
## repeatedly for a single invocation.

import ../templates/manifest
import ../types
import ./paths

var
  cached: seq[TemplateSpec]
  loaded = false

proc builtinSpecs*(): seq[TemplateSpec] =
  if not loaded:
    cached = loadSpecs(builtinTemplatesRoot(), userConfigPath())
    loaded = true
  cached

proc findBuiltinSpec*(name: string): int =
  ## Index into `builtinSpecs()`, or -1.
  result = -1
  let specs = builtinSpecs()
  for i, spec in specs:
    if spec.name == name:
      return i
