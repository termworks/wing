<img align="right" width="32%" src="./misc/pilot.png">

devpilot
===

`devpilot` is a local development workflow CLI. The binary is `dp`.

## Features

- Manage named projects with namespace, path, language, framework, template, and tag metadata.
- Discover/import projects from existing source trees.
- Manage reusable file/directory templates and apply them to new target directories with dry-run, conflict, symlink, and bundled-template flavour controls.
- Manage SSH machine entries with ProxyJump/agent-forwarding, shared ControlMaster sockets, SSH config generation, TCP/SSH health checks, and connection through stored host/interface metadata.
- Load project-scoped environment variables from `.envrc` files with a direnv-compatible loader and shell hooks (`dp env`).
- Sync a registered project to a remote machine over SSH with rsync (`dp sync`).
- Browse all stored development data through a `bobabrew`-backed terminal dashboard.
- Store user data as versioned TOML files under the platform data directory (`$XDG_DATA_HOME/devpilot` on Linux when set), with backup/import/export commands.

## Development

This repo uses `flake.nix` for the development environment. The implementation is written in Nim, but `devpilot` itself is language-neutral.

```sh
direnv allow
```

or directly:

```sh
nix develop --impure
```

Build:

```sh
make build
```

Test:

```sh
make test
```

Full local gate:

```sh
make verify
```

Run:

```sh
make run ARGS="--help"
```

After `make build`, the binary is available at:

```sh
./dp --help
```

## Usage

```sh
dp --help
dp init
dp project add my-app --path ~/code/my-app --language go --tags cli
dp project list --json
dp project discover ~/code --depth 2
dp template add basic --description "Basic app" --path ./template --language go
dp template apply basic /tmp/my-app --name my_app --dry-run
dp template apply nim /tmp/my-nim-tool --name my_nim_tool
dp template apply rust /tmp/my-rust-lib --name my_rust_lib
dp template apply cpp /tmp/my-cpp-lib --name my_cpp_lib
dp template apply python /tmp/my-python-tool --name my_python_tool
dp template apply python /tmp/my-uv-tool --name my_uv_tool --flavour uv
dp template apply python /tmp/my-pixi-tool --name my_pixi_tool --flavour pixi
dp template apply python /tmp/my-mamba-tool --name my_mamba_tool --flavour micromamba
dp machine add lab 127.0.0.1:22:local --username "$USER"
dp machine ssh-config lab
dp env hook bash        # add to ~/.bashrc: eval "$(dp env hook bash)"
dp env allow            # authorize the .envrc in the current project
dp sync add app-lab --project my-app --machine lab --remote /srv/app
dp sync run app-lab --dry-run
dp data backup create --path ./devpilot-backup
dp tui
```

When applying a template without `--name`, a missing target directory is
created and its final path component becomes the project name:

```sh
dp template apply python /tmp/my-python-tool
```

If the target already exists—including `.`—the project name is ambiguous and
must be explicit:

```sh
dp template apply python . --name my_python_tool
```

## TUI

The full-screen TUI uses [`bobabrew`](https://github.com/bresilla/bobabrew) as its Bubble Tea-style terminal backend.

```sh
dp tui
```

Running `dp` with no arguments opens the TUI.

Keys: `Left`/`Right` or `h`/`l` switch sections, `Up`/`Down` or `j`/`k` move the selection, `r` reloads data, and `q`/`Esc` quits.

Management keys:

- `Enter` shows details for the selected project, machine, or template.
- `/` filters the current section.
- `:` opens a command palette that runs any non-interactive `dp` command and reloads the dashboard.
- `a` opens a field-based add form for the current section.
- `d` deletes the selected row after typing `yes`.
- `?` shows the in-app key reference.

For CI or scripting, the TUI also has non-fullscreen modes:

```sh
dp tui --snapshot
dp tui --command "project add sample --path /tmp/sample --language go"
```

## License

This project is licensed under the MIT License. See [LICENSE.md](LICENSE.md).
