## The parts of `wing.*` that have to reach the machine.
##
## A template that only declares what it is needs none of this. One that decides — "is nix here, and
## if not should I still write a flake.nix" — needs to ask, and these are the questions it can ask.
## Everything here is a read or a message; nothing runs a command on the template's behalf.

import std/os

import ./api

proc argString(L: LuaState; idx: cint): string =
  var length: csize_t
  let text = lua_tolstring(L, idx, addr length)
  if text == nil: "" else: $text

proc wingHas(L: LuaState): cint {.cdecl.} =
  ## `wing.sys.has("nix")` — is this command on $PATH.
  let name = argString(L, 1)
  let found = name.len > 0 and findExe(name).len > 0
  lua_pushboolean(L, if found: 1 else: 0)
  1

proc wingExists(L: LuaState): cint {.cdecl.} =
  ## `wing.sys.exists(path)` — a file or a directory, either counts.
  let path = argString(L, 1)
  let found = path.len > 0 and (fileExists(path) or dirExists(path))
  lua_pushboolean(L, if found: 1 else: 0)
  1

proc wingEnv(L: LuaState): cint {.cdecl.} =
  ## `wing.sys.env("NAME")` — the variable, or nil when it is unset. Nil rather than "" so an
  ## unset variable and an empty one can be told apart.
  let name = argString(L, 1)
  let value = if name.len > 0: getEnv(name) else: ""
  if value.len == 0 and not existsEnv(name):
    lua_pushnil(L)
  else:
    discard lua_pushlstring(L, value.cstring, value.len.csize_t)
  1

proc wingWarn(L: LuaState): cint {.cdecl.} =
  ## To stderr, so a template's warnings do not land in the middle of output being piped somewhere.
  stderr.writeLine("wing: " & argString(L, 1))
  0

proc wingInfo(L: LuaState): cint {.cdecl.} =
  echo argString(L, 1)
  0

proc registerHostApi*(L: LuaState) =
  ## Hang the host functions off the `wing` table the prelude just built.
  discard lua_getglobal(L, "wing")
  if lua_type(L, -1) != LuaTTable:
    lua_pop(L, 1)
    return

  lua_createtable(L, 0, 3)
  lua_pushcclosure(L, wingHas, 0)
  lua_setfield(L, -2, "has")
  lua_pushcclosure(L, wingExists, 0)
  lua_setfield(L, -2, "exists")
  lua_pushcclosure(L, wingEnv, 0)
  lua_setfield(L, -2, "env")
  lua_setfield(L, -2, "sys")

  lua_pushcclosure(L, wingWarn, 0)
  lua_setfield(L, -2, "warn")
  lua_pushcclosure(L, wingInfo, 0)
  lua_setfield(L, -2, "info")
  lua_pop(L, 1)
