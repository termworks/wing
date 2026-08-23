# Configuration

wing embeds a Lua 5.4 interpreter and reads two kinds of Lua: a `template.lua` beside each
template, and one `init.lua` of your own.

Both are lists of statements. You assign settings, you register behaviour by calling, and the file
returns nothing — wing reads the tables back once every chunk has run.

## Where the files are

| path | what it is |
|---|---|
| `<templates>/<name>/template.lua` | a template describing itself |
| `$XDG_CONFIG_HOME/wing/templates/` | your own template tree |
| `$XDG_CONFIG_HOME/wing/init.lua` | your config: settings, overrides, placeholders, hooks |

Templates are **not** carried inside the binary — a fresh install has none until a tree is
reachable. From a wing checkout, `make templates` puts them where wing will find them:

```sh
make templates                 # -> $XDG_CONFIG_HOME/wing/templates
make templates --dest=/opt/wing/templates
```

It mirrors each bundled template individually, so a template of your own sitting in that directory
is left alone rather than deleted.

## Template roots

Every one of these is searched, **least specific first**, and a later root overrides an earlier one
by name:

```
<binary>/../share/wing/templates
<binary>/templates
./templates
<data dir>/templates
$XDG_CONFIG_HOME/wing/templates      ← yours, wins
```

`$WING_TEMPLATE_DIR` is the exception: set it and *only* that tree is used, which is what a
reproducible build and a test both want.

So your own tree looks like the bundled one:

```
~/.config/wing/templates/
  common/flake.nix       layered over the bundled common/
  go/template.lua        replaces the bundled "go" outright
  mine/
    template.lua
    base/  flavours/uv/  flavours work here too
```

### common/ layers

A template is assembled by stacking `common/` → the template's own files → its flavour, each layer
overwriting the last. Roots add one more dimension to that same stack: **every** root's `common/`
applies, in search order.

That means overriding one shared file is dropping one file. Put a `flake.nix` in
`~/.config/wing/templates/common/` and it beats the bundled one, while `.gitignore`, `LICENSE`
and `README.md` still come from the bundled tree.

A `common/` is shared extras, not a requirement — a template that only has its own files works.

## Declaring a template

```lua
local wing = require("wing")

wing.template("go", {
  description = "Go CLI app with .make.lua, flake.nix, tests, and release hooks",
  language = "go",
  framework = "cli",
  tags = { "builtin", "go", "cli" },
  nix_packages = [[
            pkgs.go
            pkgs.gopls]],
})
```

Adding a template is dropping a directory in. Nothing is recompiled.

### Flavours

A flavour is a named variant: its own packages, and its own note about the environment it sets up.

```lua
wing.template("python", {
  default_flavour = "nix",
  flavours = {
    { name = "nix", nix_packages = [[…]], environment = "…from Nix directly." },
    { name = "uv",  nix_packages = [[…]], environment = "…run `make setup`." },
  },
})
```

An array rather than a map, because the order is the order a listing shows and a manifest puts its
default first.

## Your own config

`init.lua` is loaded **after** every manifest, which is what makes overriding work: registering a
name that already exists replaces it rather than adding a second.

```lua
local wing = require("wing")

-- replace a bundled template outright
wing.template("go", { description = "my go template", language = "go" })

-- add one whose files live outside every root: an absolute dir is taken as written
wing.template("paper", { description = "a LaTeX paper", dir = "/home/me/templates/paper" })
```

Overriding a name from `init.lua` without naming a `dir` keeps the files it did not mention: the
directory is looked up across the roots, most specific first. So this replaces the description and
still builds the bundled go template:

```lua
wing.template("go", { description = "my wording", language = "go" })
```

### Placeholders

Keyed by the token they replace. A value is a string, or a function of the apply context.

```lua
wing.placeholders["{{author}}"] = "bresilla"
wing.placeholders["{{year}}"]   = function(ctx) return os.date("%Y") end
```

Your tokens are applied before the built-in ones, so `{{name}}` can be redefined.

The context carries `template`, `flavour`, `name` and `path`.

### Apply handlers

Registered rather than assigned into one hook field, so a config is as many small named functions
as it wants.

```lua
wing.on.apply(function(ctx) print("made " .. ctx.name) end)
wing.on.apply(function(ctx) os.execute("git -C " .. ctx.path .. " init -q") end)
```

They run in registration order. **One that raises is reported and the rest still run** — a mistake
in the third handler is not a reason to skip the fourth, which has nothing to do with it.

## When something is wrong

A config that cannot be read is fatal, and reported the way Lua wrote it:

```
wing config: /home/me/.config/wing/init.lua:6: syntax error near 'is'
```

A template silently missing from the listing would read as "wing lost my template" rather than
"line 6 has a typo", so wing stops instead.
