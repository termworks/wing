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
