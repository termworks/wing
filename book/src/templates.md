# Templates

Templates are copied safely with conflict detection, optional dry-runs, and
explicit symlink handling.

```sh
wing template add base --description "Base app" --path ./template
wing template apply base /tmp/new-app --name new_app --dry-run
wing template apply base /tmp/new-app --name new_app --skip-existing
```

`--name` is optional only when the target path does not exist. In that case,
wing creates the directory and uses its final path component as the project
name:

```sh
wing template apply base /tmp/new-app
# creates /tmp/new-app and uses new-app as the project name
```

If the target exists, its path is treated only as the destination and an
explicit name is required. This means `.` always requires `--name`:

```sh
wing template apply base . --name new_app
```

Bundled starter templates are available for Go, Zig, Nim, Rust, C++, and
Python:

```sh
wing init
wing template builtins list
wing template apply go /tmp/my-go-tool --name my_go_tool
wing template apply zig /tmp/my-zig-tool --name my_zig_tool
wing template apply nim /tmp/my-nim-tool --name my_nim_tool
wing template apply rust /tmp/my-rust-lib --name my_rust_lib
wing template apply cpp /tmp/my-cpp-lib --name my_cpp_lib
wing template apply python /tmp/my-python-tool --name my_python_tool
```

Python defaults to the `nix` flavour: Python, the build backend, pytest, and
Ruff are composed with `python.withPackages` in `flake.nix`, and no virtual
environment is created. Optional environment-manager flavours keep the manager
itself available through Nix:

```sh
wing template apply python /tmp/my-uv-tool --name my_uv_tool --flavour uv
wing template apply python /tmp/my-pixi-tool --name my_pixi_tool --flavour pixi
wing template apply python /tmp/my-mamba-tool --name my_mamba_tool --flavour micromamba
```

`--flavor` is accepted as an alias for `--flavour`. The generated `.make.lua`
provides `make setup`; the `uv`, `pixi`, and `micromamba` flavours create their
respective local environments only when that recipe, or one that depends on it,
is run.

## Build systems

`.make.lua` is a task runner, not a build system. It runs the commands of whatever build system the
project uses, so `make build` means `cmake --build` or `xmake build` or `go build` depending on the
template — and everything about *how* the project compiles lives in the build file, not in the
recipes.

| template | build system | flavours |
|---|---|---|
| c, cpp | xmake or CMake | `xmake` (default), `cmake` |
| zig | zig | — |
| v | v | — |
| d | dub | — |
| go, nim, rust | the language's own tool | — |
| python | pyproject | `nix` (default), `uv`, `pixi`, `micromamba` |

Where the build system is fixed but the compiler is not, the compiler is a flag rather than a
flavour: `make build --compiler dmd` for D, `make config --toolchain gcc` for C and C++.

### C and C++ are static against musl by default

`make build` links against musl and refuses to finish unless the result really is static, so what
you build is what you can copy to another machine.

The default compiler differs by language, and it is not a preference:

| | default | why |
|---|---|---|
| C | clang | `musl-clang` is the host clang pointed at musl, and C needs nothing more |
| C++ | gcc | `musl-clang` ships no C++ standard library; the musl gcc has one |

Asking for a static clang build of C++ is refused with that reason rather than failing later on the
first `#include <string>`. Both toolchains come from the flake as `MUSL_CLANG` and `MUSL_CC`.

For a faster inner loop, `make config --dynamic` uses the host toolchain and links the ordinary
way; the static check does not run on those builds.

For C and C++ the flavour picks the build system and the compiler is chosen at configure time:

```sh
make config --toolchain clang     # or gcc
make build
```

Zig is not offered as a C or C++ flavour. It compiles both perfectly well, but its build system
assumes zig-as-compiler and does not drive a host gcc or clang, which is the choice these templates
exist to give. Zig remains the build system for Zig.

Template placeholders are replaced in both file contents and file names, so
`{{snake_name}}.nimble` becomes `my_nim_tool.nimble`.

Templates live on disk, not inside the binary — see [Configuration](./config.md)
for the roots that are searched and how to add your own.

Every template shares one common base for files like `.env.lua`, `flake.nix`,
`README.md`, `.gitignore`, and `PROJECT`; each language directory overlays its
own source, build, test, and workflow files. Python adds a shared Python base
plus one selected environment flavour overlay.

A generated project is driven by `.make.lua` and `.env.lua` rather than a
Makefile and an `.envrc`, so the same `make build` / `make test` / `make verify`
recipes work in every language wing generates.
