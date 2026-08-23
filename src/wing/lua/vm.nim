## A Lua state, and the table reads wing needs from it.
##
## Everything here is stack discipline: a Lua value is only reachable while it is on the stack, so
## each reader states which index it works on and leaves the stack the height it found it.

import std/strutils

import ./api

type
  LuaVm* = object
    L*: LuaState

  LuaError* = object of CatchableError

proc newLuaVm*(): LuaVm =
  result.L = luaL_newstate()
  if result.L == nil:
    raise newException(LuaError, "could not create a Lua state")
  luaL_openlibs(result.L)

proc close*(vm: var LuaVm) =
  if vm.L != nil:
    lua_close(vm.L)
    vm.L = nil

proc popError*(L: LuaState): string =
  ## Take the message a failed load or call left on top of the stack.
  var length: csize_t
  let text = lua_tolstring(L, -1, addr length)
  result = if text == nil: "unknown Lua error" else: $text
  lua_pop(L, 1)

proc run*(vm: LuaVm; source, chunkName: string) =
  ## Load and execute a chunk. Raises with Lua's own message, which carries the line number.
  if luaL_loadbufferx(vm.L, source.cstring, source.len.csize_t,
      chunkName.cstring, nil) != LuaOk:
    raise newException(LuaError, popError(vm.L))
  if lua_pcall(vm.L, 0, 0, 0) != LuaOk:
    raise newException(LuaError, popError(vm.L))

# ------------------------------------------------------------------ reading ----

proc toStr*(L: LuaState; idx: cint): string =
  ## The value at `idx` as a string. Numbers convert; anything else is empty.
  if lua_type(L, idx) notin [LuaTString, LuaTNumber]:
    return ""
  var length: csize_t
  let text = lua_tolstring(L, idx, addr length)
  if text == nil: "" else: newString(0) & $text

proc fieldStr*(L: LuaState; tbl: cint; key, fallback: string): string =
  ## `tbl[key]` as a string, or `fallback` when absent.
  let at = lua_absindex(L, tbl)
  discard lua_getfield(L, at, key.cstring)
  result = if lua_type(L, -1) == LuaTNil: fallback else: toStr(L, -1)
  lua_pop(L, 1)

proc fieldBool*(L: LuaState; tbl: cint; key: string; fallback: bool): bool =
  let at = lua_absindex(L, tbl)
  discard lua_getfield(L, at, key.cstring)
  result = if lua_type(L, -1) == LuaTNil: fallback else: lua_toboolean(L, -1) != 0
  lua_pop(L, 1)

proc fieldStrSeq*(L: LuaState; tbl: cint; key: string): seq[string] =
  ## `tbl[key]` as an array of strings. A bare string counts as a one-element list, because a
  ## config that writes `tags = "builtin"` means the obvious thing.
  let at = lua_absindex(L, tbl)
  discard lua_getfield(L, at, key.cstring)
  case lua_type(L, -1)
  of LuaTString:
    result = @[toStr(L, -1)]
  of LuaTTable:
    let n = lua_rawlen(L, -1).int
    for i in 1 .. n:
      discard lua_rawgeti(L, -1, i.LuaInteger)
      let item = toStr(L, -1).strip()
      if item.len > 0:
        result.add(item)
      lua_pop(L, 1)
  else:
    discard
  lua_pop(L, 1)

proc keysOf*(L: LuaState; tbl: cint): seq[string] =
  ## The string keys of the table at `tbl`, in Lua's own iteration order.
  let at = lua_absindex(L, tbl)
  if lua_type(L, at) != LuaTTable:
    return
  lua_pushnil(L)
  while lua_next(L, at) != 0:
    # `lua_next` leaves key at -2 and value at -1. Reading the key with lua_tolstring would
    # rewrite it in place and confuse the next iteration, so only string keys are taken.
    if lua_type(L, -2) == LuaTString:
      result.add(toStr(L, -2))
    lua_pop(L, 1)

proc hasField*(L: LuaState; tbl: cint; key: string): bool =
  let at = lua_absindex(L, tbl)
  discard lua_getfield(L, at, key.cstring)
  result = lua_type(L, -1) != LuaTNil
  lua_pop(L, 1)

# ------------------------------------------------------------------ calling ----

proc pushStrTable*(L: LuaState; pairs: openArray[(string, string)]) =
  ## A plain string->string table, which is every context wing hands to a config.
  lua_createtable(L, 0, pairs.len.cint)
  for pair in pairs:
    discard lua_pushlstring(L, pair[1].cstring, pair[1].len.csize_t)
    lua_setfield(L, -2, pair[0].cstring)

proc callWithContext*(L: LuaState; fnIdx: cint; ctx: openArray[(string, string)];
                      results: cint): tuple[ok: bool; err: string] =
  ## Call the function at `fnIdx` with one context table. On success `results` values are left on
  ## the stack for the caller to read and pop; on failure nothing is.
  lua_pushvalue(L, fnIdx)
  pushStrTable(L, ctx)
  if lua_pcall(L, 1, results, 0) != LuaOk:
    return (false, popError(L))
  (true, "")
