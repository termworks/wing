## Reads template declarations out of Lua.
##
## A template describes itself in a `template.lua` beside its files, so adding one is dropping a
## directory in rather than editing Nim and recompiling. User config is loaded after the bundled
## manifests, which is what makes overriding a bundled name work: same key, later wins.

import std/[algorithm, os]

import ../lua/api
import ../lua/prelude
import ../lua/vm
import ../types

const
  ManifestName* = "template.lua"
  UserConfigName* = "init.lua"

proc userConfigPath*(): string =
  ## `$XDG_CONFIG_HOME/wing/init.lua`, or the usual place under $HOME.
  let xdg = getEnv("XDG_CONFIG_HOME")
  let root = if xdg.len > 0: xdg else: getHomeDir() / ".config"
  root / "wing" / UserConfigName

proc readFlavours(L: LuaState; specIdx: cint): seq[TemplateFlavour] =
  ## `spec.flavours` is an array of `{ name = ..., nix_packages = ..., environment = ... }`.
  ##
  ## An array rather than a map keyed by name, because the order is the order a listing shows and
  ## a manifest puts its default first. Lua does not define an iteration order for string keys, so
  ## a map here would reshuffle `wing template builtins` between runs.
  let at = lua_absindex(L, specIdx)
  discard lua_getfield(L, at, "flavours")
  if lua_type(L, -1) == LuaTTable:
    let tbl = lua_gettop(L)
    for i in 1 .. lua_rawlen(L, tbl).int:
      discard lua_rawgeti(L, tbl, i.LuaInteger)
      if lua_type(L, -1) == LuaTTable:
        let name = fieldStr(L, -1, "name", "")
        if name.len > 0:
          result.add(TemplateFlavour(
            name: name,
            nixPackages: fieldStr(L, -1, "nix_packages", ""),
            environment: fieldStr(L, -1, "environment", "")
          ))
      lua_pop(L, 1)
  lua_pop(L, 1)

proc readSpecs(L: LuaState): seq[TemplateSpec] =
  ## Everything sitting in `wing.templates` after the chunks have run.
  discard lua_getglobal(L, "wing")
  if lua_type(L, -1) != LuaTTable:
    lua_pop(L, 1)
    return
  discard lua_getfield(L, -1, "templates")
  if lua_type(L, -1) != LuaTTable:
    lua_pop(L, 2)
    return

  let tbl = lua_gettop(L)
  for name in keysOf(L, tbl):
    discard lua_getfield(L, tbl, name.cstring)
    if lua_type(L, -1) == LuaTTable:
      let spec = lua_gettop(L)
      result.add(TemplateSpec(
        name: name,
        description: fieldStr(L, spec, "description", ""),
        dir: fieldStr(L, spec, "dir", name),
        language: fieldStr(L, spec, "language", ""),
        framework: fieldStr(L, spec, "framework", ""),
        tags: fieldStrSeq(L, spec, "tags"),
        nixPackages: fieldStr(L, spec, "nix_packages", ""),
        flavours: readFlavours(L, spec),
        defaultFlavour: fieldStr(L, spec, "default_flavour", "")
      ))
    lua_pop(L, 1)
  lua_pop(L, 2)
  result.sort(proc (a, b: TemplateSpec): int = cmp(a.name, b.name))

proc manifestPaths*(root: string): seq[string] =
  ## Every `<root>/<dir>/template.lua`, in directory order.
  if root.len == 0 or not dirExists(root):
    return
  for kind, path in walkDir(root):
    if kind == pcDir:
      let manifest = path / ManifestName
      if fileExists(manifest):
        result.add(manifest)
  result.sort()

proc loadSpecs*(root: string; userConfig = ""): seq[TemplateSpec] =
  ## Run the bundled manifests, then the user's config, and read back what they registered.
  ##
  ## A manifest that raises is fatal and names its own file and line: a template that cannot say
  ## what it is would otherwise be silently missing from the listing.
  var vm = newLuaVm()
  defer: vm.close()
  vm.run(WingPrelude, "=[wing prelude]")

  for manifest in manifestPaths(root):
    vm.run(readFile(manifest), "@" & manifest)

  if userConfig.len > 0 and fileExists(userConfig):
    vm.run(readFile(userConfig), "@" & userConfig)

  result = readSpecs(vm.L)
