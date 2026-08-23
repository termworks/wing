local wing = require("wing")

-- Odin is its own compiler and build system, the way Zig and V are, so there is no build-system
-- flavour to choose. `odinfmt` comes from ols rather than from odin itself.
wing.template("odin", {
  description = "Odin CLI app with .make.lua, flake.nix, tests, and release hooks",
  language = "odin",
  framework = "cli",
  tags = { "builtin", "odin", "cli" },
  nix_packages = [[
            pkgs.odin
            pkgs.ols]],
})
