local wing = require("wing")

wing.template("cpp", {
  description = "C++ library starter with CMake, .make.lua, flake.nix, tests, and release hooks",
  language = "cpp",
  framework = "library",
  tags = { "builtin", "cpp", "library" },
  nix_packages = [[
            pkgs.cmake
            pkgs.gcc
            pkgs.gdb
            pkgs.clang-tools]],
})
