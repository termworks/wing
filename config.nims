import std/os

# Lua comes from nixpkgs (see flake.nix); nothing of it is vendored here. WING_LUA picks which
# build to link: the static release sets it to the musl one, and everything else falls back to the
# glibc one the dev shell exports. Kept here rather than in the recipes so that `nimble test` and a
# bare `nim c` get the same flags as `make build`.
let luaRoot = block:
  let chosen = getEnv("WING_LUA")
  if chosen.len > 0: chosen else: getEnv("LUA_DEV")

if luaRoot.len > 0:
  switch("passC", "-I" & luaRoot / "include")
  switch("passL", "-L" & luaRoot / "lib")
switch("passL", "-llua")
switch("passL", "-lm")
