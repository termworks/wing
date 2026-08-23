# Templates as plugins

A template is a directory you can install from somewhere else, and it can carry logic of its own.
It is still called a template, and the bundled ones still ship — what changed is that a template is
no longer only a pile of files.

```sh
wing template install ~/src/my-template
wing template install github:someone/repo@v1.2.0
wing template installed
wing template allow my-template
wing template uninstall my-template
```

## What a template is

```text
my-template/
  template.lua    what it declares — read before you decide to trust it
  init.lua        optional: what it does — loaded only when the template is used
  …the files
```

`template.lua` is the manifest and it is inert by design: it is read with the ordinary `wing`
prelude and nothing that reaches the machine, so `install` can show you what a template *claims*
without running it. `init.lua` is where behaviour lives, and it is not read at install time at all.

Neither file is copied into the projects a template generates.

## Installing

A source is a directory on this machine, or a git repository **at a revision**:

```sh
wing template install ./my-template
wing template install github:user/repo@v1.0.0
wing template install https://example.com/t.git@a1b2c3d
wing template install file:///srv/mirror/t.git@v2      # a local mirror
```

The revision is not optional for a git source. Without one, `install` takes whatever the branch
says today and something else tomorrow — and the trust check below would then refuse to load it the
morning after every upstream commit, which teaches people to run `allow` without reading. That is
worse than having no gate.

Installing prints what the template declares, then keeps it under
`$XDG_DATA_HOME/wing/templates/<name>` and registers it, so `wing template apply` works straight
away.

## Trust

`install` records what the template's `.lua` files hashed to. `wing template installed` recomputes
and compares:

```
  my-template   github:user/repo@v1.0.0   CHANGED — run `wing template allow my-template`
```

So editing an installed template, or pulling a new revision over it, is visible rather than picked
up silently. `wing template allow <name>` agrees to what is there now.

Only `.lua` is hashed. Editing a README is not a change to what a template will do, and hashing it
would make every documentation edit a refusal.

A template wing did not install — the bundled tree, or something you wrote by hand in your config
directory — is *unmanaged*, not untrusted. Gating those would be a refusal with no remedy.

## Logic

`init.lua` runs when the template is used. Its hooks are scoped to the template it belongs to.

### Deciding whether to apply at all

```lua
local wing = require("wing")

wing.on.check(function(ctx)
  if not wing.sys.has("nix") then
    wing.warn("nix is not installed — the flake will be written but you cannot enter the shell")
  end
end)
```

Return `{ refuse = "why" }` to stop the apply. Returning nothing carries on, which is the common
case: warning is usually the right answer, and it is what happens by default.

### Deciding file by file

```lua
wing.on.file(function(file)
  if file.rel == "flake.nix" and not wing.sys.has("nix") then
    return { skip = true }
  end
end)
```

A skipped file is left out of the plan as well, so `--dry-run` shows what would really be written.

### What a template can ask

| | |
|---|---|
| `wing.sys.has(cmd)` | is this command on `$PATH` |
| `wing.sys.exists(path)` | a file or a directory, either counts |
| `wing.sys.env(name)` | the variable, or `nil` when unset |
| `wing.warn(msg)` | to stderr |
| `wing.info(msg)` | to stdout |

All reads and messages. Nothing here runs a command on the template's behalf.

The context every hook receives carries `template`, `flavour`, `name` and `path`; `on.file` adds
`rel`.

### Registered from a user config instead

The same hooks work in `~/.config/wing/init.lua`. Registered there they have no owning template, so
they apply to **every** template — one rule, and it reads the same in both places.

## What it cannot do

- **Sandbox anything.** A template's `init.lua` is Lua with the `wing` API. The hash gate decides
  whether you trust it, not what it may do once you have.
- **Resolve dependencies, or find templates by name.** There is no registry. A template that needs
  another says so in prose.
- **Survive its own bugs silently.** A hook that raises is reported, naming the template, and the
  remaining hooks still run.
