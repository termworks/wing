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

proc readSpecs*(L: LuaState): seq[TemplateSpec] =
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

proc openConfig*(root: string; userConfig = ""): LuaVm =
  ## Run the bundled manifests, then the user's config, and hand back the state they registered
  ## into. The state stays open because placeholders and apply handlers are Lua functions that are
  ## called later, during an apply.
  ##
  ## A manifest that raises is fatal and names its own file and line: a template that cannot say
  ## what it is would otherwise be silently missing from the listing. The user config is loaded
  ## last, which is what makes registering a bundled name again override it.
  result = newLuaVm()
  result.run(WingPrelude, "=[wing prelude]")

  for manifest in manifestPaths(root):
    result.run(readFile(manifest), "@" & manifest)

  if userConfig.len > 0 and fileExists(userConfig):
    result.run(readFile(userConfig), "@" & userConfig)

proc placeholderOverrides*(L: LuaState;
    ctx: openArray[(string, string)]): seq[(string, string)] =
  ## `wing.placeholders` as token/value pairs. A value is a string, or a function of the apply
  ## context returning one -- which is what lets a token be computed per project rather than fixed.
  discard lua_getglobal(L, "wing")
  if lua_type(L, -1) != LuaTTable:
    lua_pop(L, 1); return
  discard lua_getfield(L, -1, "placeholders")
  if lua_type(L, -1) != LuaTTable:
    lua_pop(L, 2); return

  let tbl = lua_gettop(L)
  for token in keysOf(L, tbl):
    discard lua_getfield(L, tbl, token.cstring)
    case lua_type(L, -1)
    of LuaTString, LuaTNumber:
      result.add((token, toStr(L, -1)))
    of LuaTFunction:
      let call = callWithContext(L, lua_gettop(L), ctx, 1)
      if call.ok:
        result.add((token, toStr(L, -1)))
        lua_pop(L, 1)
      else:
        stderr.writeLine("wing: placeholder " & token & ": " & call.err)
    else:
      discard
    lua_pop(L, 1)
  lua_pop(L, 2)

proc runApplyHandlers*(L: LuaState; ctx: openArray[(string, string)]) =
  ## Every `wing.on.apply` handler, in registration order.
  ##
  ## One that raises is reported and the rest still run: a mistake in the third handler is not a
  ## reason to skip the fourth, which has nothing to do with it.
  discard lua_getglobal(L, "wing")
  if lua_type(L, -1) != LuaTTable:
    lua_pop(L, 1); return
  discard lua_getfield(L, -1, "on")
  if lua_type(L, -1) != LuaTTable:
    lua_pop(L, 2); return
  discard lua_getfield(L, -1, "_apply")
  if lua_type(L, -1) != LuaTTable:
    lua_pop(L, 3); return

  let tbl = lua_gettop(L)
  for i in 1 .. lua_rawlen(L, tbl).int:
    discard lua_rawgeti(L, tbl, i.LuaInteger)
    if lua_type(L, -1) == LuaTFunction:
      let call = callWithContext(L, lua_gettop(L), ctx, 0)
      if not call.ok:
        stderr.writeLine("wing: on.apply handler " & $i & ": " & call.err)
    lua_pop(L, 1)
  lua_pop(L, 3)
