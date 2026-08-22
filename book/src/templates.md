# Templates

Templates are copied safely with conflict detection, optional dry-runs, and
explicit symlink handling.

```sh
dp template add base --description "Base app" --path ./template
dp template apply base /tmp/new-app --name new_app --dry-run
dp template apply base /tmp/new-app --name new_app --skip-existing
```

`--name` is optional only when the target path does not exist. In that case,
devpilot creates the directory and uses its final path component as the project
name:

```sh
dp template apply base /tmp/new-app
# creates /tmp/new-app and uses new-app as the project name
```

If the target exists, its path is treated only as the destination and an
explicit name is required. This means `.` always requires `--name`:

```sh
dp template apply base . --name new_app
```

Bundled starter templates are available for Go, Zig, Nim, Rust, C++, and
Python:

```sh
dp init
dp template builtins list
dp template apply go /tmp/my-go-tool --name my_go_tool
dp template apply zig /tmp/my-zig-tool --name my_zig_tool
dp template apply nim /tmp/my-nim-tool --name my_nim_tool
dp template apply rust /tmp/my-rust-lib --name my_rust_lib
dp template apply cpp /tmp/my-cpp-lib --name my_cpp_lib
dp template apply python /tmp/my-python-tool --name my_python_tool
```

Python defaults to the `nix` flavour: Python, the build backend, pytest, and
Ruff are composed with `python.withPackages` in `flake.nix`, and no virtual
environment is created. Optional environment-manager flavours keep the manager
itself available through Nix:

```sh
dp template apply python /tmp/my-uv-tool --name my_uv_tool --flavour uv
dp template apply python /tmp/my-pixi-tool --name my_pixi_tool --flavour pixi
dp template apply python /tmp/my-mamba-tool --name my_mamba_tool --flavour micromamba
```

`--flavor` is accepted as an alias for `--flavour`. The generated Makefile
provides `make setup`; the `uv`, `pixi`, and `micromamba` flavours create their
respective local environments only when that target or another dependent target
is run.

Template placeholders are replaced in both file contents and file names, so
`{{snake_name}}.nimble` becomes `my_nim_tool.nimble`.

The bundled templates are embedded in the `dp` binary. `dp init` writes them to
`$XDG_DATA_HOME/devpilot/templates` and registers `go`, `zig`, `nim`, `rust`,
`cpp`, and `python`.

The embedded templates share one common base for files like `.envrc`,
`flake.nix`, `README.md`, `.gitignore`, and `PROJECT`; each language directory
only overlays its unique source, build, test, and workflow files. Python adds a
shared Python base plus one selected environment flavour overlay.
