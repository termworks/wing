## Bundled starter templates and their Nix package sets.

import ../types

const
  GoNixPackages* = "            pkgs.go\n" &
      "            pkgs.gopls\n" &
      "            pkgs.gotools\n" &
      "            pkgs.go-tools\n" &
      "            pkgs.delve\n" &
      "            pkgs.golangci-lint\n" &
      "            pkgs.goreleaser"

  ZigNixPackages* = "            pkgs.zig\n" &
      "            pkgs.zls"

  NimNixPackages* = "            pkgs.nim\n" &
      "            pkgs.nimble\n" &
      "            pkgs.nimlsp\n" &
      "            pkgs.nimlangserver"

  RustNixPackages* = "            pkgs.rustc\n" &
      "            pkgs.cargo\n" &
      "            pkgs.rustfmt\n" &
      "            pkgs.clippy\n" &
      "            pkgs.rust-analyzer"

  CppNixPackages* = "            pkgs.cmake\n" &
      "            pkgs.gcc\n" &
      "            pkgs.gdb\n" &
      "            pkgs.clang-tools"

  PythonNixPackages* = "            (pkgs.python3.withPackages (pythonPackages: with pythonPackages; [\n" &
      "              build\n" &
      "              hatchling\n" &
      "              pytest\n" &
      "            ]))\n" &
      "            pkgs.ruff"

  PythonUvNixPackages* = "            pkgs.python3\n" &
      "            pkgs.uv"

  PythonPixiNixPackages* = "            pkgs.pixi"

  PythonMicromambaNixPackages* = "            pkgs.micromamba"

  BuiltinTemplates*: array[6, BuiltinTemplate] = [
    BuiltinTemplate(
      name: "go",
      description: "Go CLI app with Makefile, flake.nix, tests, and release hooks",
      dir: "go",
      language: "go",
      framework: "cli",
      tags: "builtin,go,cli",
      nixPackages: GoNixPackages
    ),
    BuiltinTemplate(
      name: "zig",
      description: "Zig CLI app with build.zig, Makefile, flake.nix, and release hooks",
      dir: "zig",
      language: "zig",
      framework: "cli",
      tags: "builtin,zig,cli",
      nixPackages: ZigNixPackages
    ),
    BuiltinTemplate(
      name: "nim",
      description: "Nim CLI app with nimble, Makefile, flake.nix, tests, and release hooks",
      dir: "nim",
      language: "nim",
      framework: "cli",
      tags: "builtin,nim,cli",
      nixPackages: NimNixPackages
    ),
    BuiltinTemplate(
      name: "rust",
      description: "Rust library starter with Cargo, Makefile, flake.nix, tests, and release hooks",
      dir: "rust",
      language: "rust",
      framework: "library",
      tags: "builtin,rust,library",
      nixPackages: RustNixPackages
    ),
    BuiltinTemplate(
      name: "cpp",
      description: "C++ library starter with CMake, Makefile, flake.nix, tests, and release hooks",
      dir: "cpp",
      language: "cpp",
      framework: "library",
      tags: "builtin,cpp,library",
      nixPackages: CppNixPackages
    ),
    BuiltinTemplate(
      name: "python",
      description: "Python app with a pure Nix default and optional uv, pixi, or micromamba environments",
      dir: "python",
      language: "python",
      framework: "cli",
      tags: "builtin,python,cli",
      nixPackages: PythonNixPackages,
      flavours: "nix,uv,pixi,micromamba",
      defaultFlavour: "nix"
    )
  ]
