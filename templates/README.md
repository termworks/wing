# devpilot bundled templates

Install these into your devpilot template registry:

```sh
dp init
```

Then create projects:

```sh
dp template apply go /tmp/my-go-tool --name my_go_tool
dp template apply zig /tmp/my-zig-tool --name my_zig_tool
dp template apply nim /tmp/my-nim-tool --name my_nim_tool
dp template apply rust /tmp/my-rust-lib --name my_rust_lib
dp template apply cpp /tmp/my-cpp-lib --name my_cpp_lib
dp template apply python /tmp/my-python-tool --name my_python_tool
dp template apply python /tmp/my-uv-tool --name my_uv_tool --flavour uv
dp template apply python /tmp/my-pixi-tool --name my_pixi_tool --flavour pixi
dp template apply python /tmp/my-mamba-tool --name my_mamba_tool --flavour micromamba
```

For a missing target, `--name` may be omitted and the target directory name is
used as the project name. Existing targets, including `.`, always require an
explicit `--name`.

The apply command replaces placeholders in file contents and file names.

Layout:

- `common/` contains shared files.
- `go/`, `zig/`, `nim/`, `rust/`, and `cpp/` overlay only language-specific files.
- `python/base/` contains shared Python files.
- `python/flavours/` contains `nix`, `uv`, `pixi`, and `micromamba` overlays.

Python uses the `nix` flavour by default. It sources Python packages directly
from Nix and does not create a virtual environment. The other flavours install
their environment manager through Nix and create the manager-specific local
environment with `make setup`.
