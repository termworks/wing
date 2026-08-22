# Environment (`dp env`)

`dp env` is a direnv-compatible environment loader. The `.envrc` file is
executable bash and the source of truth. devpilot watches the current directory
(and parents) for a `.envrc`, runs it in a bash subshell, captures the resulting
exported variables, and applies only the diff to your shell.

## Shell hook

Add one line to your shell rc file:

```sh
# bash (~/.bashrc) or zsh (~/.zshrc)
eval "$(dp env hook bash)"     # or: zsh
# fish (~/.config/fish/config.fish)
dp env hook fish | source
```

Before each prompt the hook calls `dp env export <shell>`, which loads or
unloads variables depending on the current directory.

## Authorization

`.envrc` is executable bash, so it must be explicitly authorized before it runs:

```sh
cd ~/code/myapp
echo 'export DATABASE_URL=postgres://localhost/myapp' > .envrc
dp env allow          # authorizes the .envrc in the current directory
```

Editing the `.envrc` invalidates the authorization (the file hash changes); run
`dp env allow` again. Revoke with `dp env deny`.

## The `.envrc` file

A trimmed copy of direnv's stdlib is sourced before your `.envrc`, so these
helpers are available: `PATH_add`, `path_add`, `dotenv`, `source_env`,
`source_env_up`, `watch_file`, `strict_env`, `expand_path`, `find_up`, among
others.

```sh
export DATABASE_URL=postgres://localhost/myapp
export LOG_LEVEL=debug
PATH_add bin
dotenv_if_exists .env.local
```

## Commands

```sh
dp env export bash|zsh|fish|json   # emit the env diff (hook-driven)
dp env hook bash|zsh|fish          # print the shell hook
dp env allow [PATH]                # authorize the .envrc at PATH (default: cwd)
dp env deny [PATH]                 # revoke authorization
dp env status                      # cwd resolution, allow state, loaded vars
```

## How it works

State travels per-shell-session via the `DP_DIFF` environment variable, which
holds a *reversible* diff (original values + applied values). On each prompt:

1. devpilot reverts the previously-applied overlay, restoring a pristine
   baseline.
2. it re-runs `.envrc` against that pristine baseline (so values like `PATH`
   never accumulate across cycles);
3. it diffs the current shell state against the freshly-loaded environment and
   emits only the `export`/`unset` changes for the shell to `eval`.

This mirrors direnv's `DIRENV_DIFF` model.
