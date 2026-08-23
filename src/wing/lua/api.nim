## Raw Lua 5.4 C API — only the calls wing makes.
##
## Lua itself is not vendored: it comes from nixpkgs, pinned by flake.lock, and `config.nims`
## points the compiler at its headers and archive. This file and `vm.nim` are the whole of the
## Lua integration that lives in this repository.

{.push importc, cdecl.}

type
  lua_State* {.importc: "lua_State", header: "lua.h",
      incompleteStruct.} = object
  LuaState* = ptr lua_State
  LuaCFunction* = proc (L: LuaState): cint {.cdecl.}
  LuaInteger* = int64
  LuaNumber* = float64
  # `typedef intptr_t lua_KContext` — an integer, not a pointer.
  LuaKContext* = int

const
  LuaOk* = cint(0)
  LuaErrRun* = cint(2)
  LuaErrSyntax* = cint(3)
  LuaErrMem* = cint(4)

  LuaTNone* = cint(-1)
  LuaTNil* = cint(0)
  LuaTBoolean* = cint(1)
  LuaTNumber* = cint(3)
  LuaTString* = cint(4)
  LuaTTable* = cint(5)
  LuaTFunction* = cint(6)

  # -LUAI_MAXSTACK - 1000, with LUAI_MAXSTACK at its 64-bit default.
  LuaRegistryIndex* = cint(-1001000)

# ---------------------------------------------------------------------- state ----

{.push header: "lauxlib.h".}
proc luaL_newstate*(): LuaState
proc luaL_loadbufferx*(L: LuaState; buff: cstring; sz: csize_t; name: cstring;
                       mode: cstring): cint
proc luaL_ref*(L: LuaState; t: cint): cint
proc luaL_unref*(L: LuaState; t: cint; r: cint)
{.pop.}

{.push header: "lualib.h".}
proc luaL_openlibs*(L: LuaState)
{.pop.}

{.push header: "lua.h".}
proc lua_close*(L: LuaState)
proc lua_pcallk*(L: LuaState; nargs, nresults, errfunc: cint; ctx: LuaKContext;
                 k: pointer): cint
proc lua_error*(L: LuaState): cint

# ---------------------------------------------------------------------- stack ----

proc lua_gettop*(L: LuaState): cint
proc lua_settop*(L: LuaState; idx: cint)
proc lua_type*(L: LuaState; idx: cint): cint
proc lua_typename*(L: LuaState; tp: cint): cstring
proc lua_absindex*(L: LuaState; idx: cint): cint
proc lua_pushvalue*(L: LuaState; idx: cint)

# ---------------------------------------------------------------------- read ----

proc lua_tolstring*(L: LuaState; idx: cint; len: ptr csize_t): cstring
proc lua_tointegerx*(L: LuaState; idx: cint; isnum: ptr cint): LuaInteger
proc lua_tonumberx*(L: LuaState; idx: cint; isnum: ptr cint): LuaNumber
proc lua_toboolean*(L: LuaState; idx: cint): cint
proc lua_rawlen*(L: LuaState; idx: cint): csize_t

# ---------------------------------------------------------------------- write ----

proc lua_pushnil*(L: LuaState)
proc lua_pushboolean*(L: LuaState; b: cint)
proc lua_pushinteger*(L: LuaState; n: LuaInteger)
proc lua_pushlstring*(L: LuaState; s: cstring; len: csize_t): cstring
proc lua_pushcclosure*(L: LuaState; fn: LuaCFunction; n: cint)
proc lua_pushlightuserdata*(L: LuaState; p: pointer)
proc lua_touserdata*(L: LuaState; idx: cint): pointer

# ---------------------------------------------------------------------- tables ----

proc lua_createtable*(L: LuaState; narr, nrec: cint)
proc lua_getfield*(L: LuaState; idx: cint; k: cstring): cint
proc lua_setfield*(L: LuaState; idx: cint; k: cstring)
proc lua_geti*(L: LuaState; idx: cint; n: LuaInteger): cint
proc lua_seti*(L: LuaState; idx: cint; n: LuaInteger)
proc lua_rawgeti*(L: LuaState; idx: cint; n: LuaInteger): cint
proc lua_next*(L: LuaState; idx: cint): cint
proc lua_getglobal*(L: LuaState; name: cstring): cint
proc lua_setglobal*(L: LuaState; name: cstring)
{.pop.}

{.pop.}

# The C API spells these as macros, which expand fine at the call site.
proc lua_pop*(L: LuaState; n: cint) {.importc: "lua_pop", header: "lua.h", cdecl.}
proc lua_pushstring*(L: LuaState; s: cstring): cstring
  {.importc: "lua_pushstring", header: "lua.h", cdecl.}
proc lua_upvalueindex*(i: cint): cint
  {.importc: "lua_upvalueindex", header: "lua.h", cdecl.}

proc lua_pcall*(L: LuaState; nargs, nresults, errfunc: cint): cint =
  lua_pcallk(L, nargs, nresults, errfunc, 0, nil)
