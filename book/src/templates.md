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
| odin | odin | — |
| c3 | c3c | — |
| ocaml | dune | — |
| vala | meson (valac emits C) | — |
| d | dub | — |
| haskell | cabal | — |
| crystal | crystal + shards | — |
| carbon | carbon | — |
| mojo | mojo | — |
| go, nim, rust | the language's own tool | — |
| python | pyproject | `nix` (default), `uv`, `pixi`, `micromamba` |

### Releasing

Every template ships the same `.github/workflows/release.yml`, and it is the same one in every
language — only the build command and what goes in the tarball differ.

```sh
make release --type patch    # bump, changelog, commit, tag, push
```

Pushing the `v*` tag is the whole release. The workflow then:

1. builds on `ubuntu-latest` and `ubuntu-24.04-arm`, **inside the project's own flake** — the
   binary that ships was compiled by the toolchain the dev shell hands you, and a second pin in the
   workflow would be a second thing to keep in step;
2. packages `<name>-<version>-linux-<arch>.tar.gz` with the artifact, `README` and `LICENSE`;
3. checksums every asset into one `SHA256SUMS`;
4. creates the release the tag points at — it does not wait for one to exist — and uploads.

What lands in the tarball is whatever the project produces: the binary for an application, the
static library and its headers for the C and C++ templates, the `.crate` for Rust, and the wheel
and sdist for Python.

Two templates build for amd64 only: Carbon publishes a prebuilt x86_64 nightly and Mojo a linux-64
conda package, so there is no arm64 toolchain for the flake to unpack.

`workflow_dispatch` takes an existing tag, for rebuilding an asset that failed without cutting
another release.

### A generated project is a repository

`wing template apply` finishes by running `git init`, staging what it wrote, and `git flow init -d
--preset=classic`, so a new project starts on `develop` with `main` beside it, the `feature/`,
`release/` and `hotfix/` prefixes configured, and one commit holding the generated files. The
recipes assume this: `make release` runs `git-rel`, which refuses to run anywhere but `develop`.

Staging is not a nicety. A flake only sees files git knows about, so a repository where nothing is
tracked answers `nix develop` with `Path 'flake.nix' ... is not tracked by Git` — and `.env.lua`
brings that shell up on every `cd`.

Three cases leave it alone, each saying so on the last line of the apply:

- `--no-git`, for generating something that is not a project of its own
- the target is already inside a checkout — a nested repository the outer one cannot see into is
  never what was wanted
- `git-flow` is not installed, or git has no author identity to commit with; the repository is
  still created, and the line names which of the two it was

### Where the version lives

There is no version file of wing's own. Each generated project keeps its version where its own
language already keeps it, which is also where [`veri`](https://github.com/bresilla) — the bumper
behind `make release` — looks for it:

| template | version read from |
|---|---|
| rust | `Cargo.toml` |
| nim | `*.nimble` |
| v | `v.mod` |
| go | the `version` literal in `src/main.go` (go.mod has no version field) |
| d | `dub.json` |
| python | `pyproject.toml` |
| c, cpp (xmake) | `set_version` in `xmake.lua` |
| c, cpp (cmake) | `project(... VERSION ...)` in `CMakeLists.txt` |
| crystal | `shard.yml` |
| haskell | the `*.cabal` file |
| ocaml | `dune-project` |
| vala | `meson.build` |
| c3 | `project.json` |
| carbon, mojo, odin, zig | the latest git tag |

The last row is for languages with no manifest to keep a version in. Zig is in it on purpose: a
`build.zig.zon` also needs a `fingerprint` unique to each project, which zig generates and a
template cannot ship — and an application does not need the manifest at all.

`make version` prints what the recipes read, and `make build` reports it beside the binary.

### Carbon and Mojo bring their own compiler

Neither is in nixpkgs, and neither can be installed from a distribution's package manager: Carbon
publishes prebuilt nightlies and nothing else, and Mojo is a closed-source conda package under
Modular's own licence. So the template declares the derivation that unpacks one, and the flake it
generates *is* how you get a toolchain. Without nix these two templates produce a project you
cannot build, which is what their `init.lua` warns about at generation time.

That derivation is pinned to an exact version and hash, because nix cannot express "whatever is
newest" — `fetchurl` needs the hash before it fetches. For Carbon, whose only releases are
nightlies, moving the pin is therefore a command rather than a default:

```sh
make toolchain      # read the newest nightly, hash it, rewrite the two lines in flake.nix
```

It rewrites the generated project's own `flake.nix`, so a checkout keeps building against the
toolchain it was written for until somebody decides otherwise.

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
`{{snake_name}}.nimble` becomes `my_nim_tool.nimble`. The set is `{{PROJECT_NAME}}`,
`{{project_name}}`, `{{PROJECT-NAME}}`, `{{project-name}}`, `{{NAME}}`, `{{name}}`,
`{{kebab_name}}`, `{{snake_name}}`, `{{PascalName}}` and `{{Snake_name}}` — the last two for
languages whose identifiers must start with a capital: `DemoThing` for a Haskell module,
`Demo_thing` for an OCaml one. `{{year}}` is the year the project was generated, for the copyright
line in `LICENSE`.

Templates live on disk, not inside the binary — see [Configuration](./config.md)
for the roots that are searched and how to add your own.

Every template shares one common base for files like `.env.lua`, `flake.nix`,
`README.md`, `LICENSE`, and `.gitignore`; each language directory overlays its
own source, build, test, and workflow files. Python adds a shared Python base
plus one selected environment flavour overlay.

A generated project is driven by `.make.lua` and `.env.lua` rather than a
Makefile and an `.envrc`, so the same `make build` / `make test` / `make verify`
recipes work in every language wing generates.
