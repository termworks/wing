# Configuration

wing embeds a Lua 5.4 interpreter and reads two kinds of Lua: a `template.lua` beside each
template, and one `init.lua` of your own.

Both are lists of statements. You assign settings, you register behaviour by calling, and the file
returns nothing — wing reads the tables back once every chunk has run.

## Where the files are

| path | what it is |
|---|---|
| `<templates>/<name>/template.lua` | a template describing itself |
| `$XDG_CONFIG_HOME/wing/init.lua` | your config: add, override, extend |

The template tree is found in this order: `$WING_TEMPLATE_DIR`, then `<data dir>/templates`, then
`./templates`, then beside the binary. Templates are **not** carried inside the binary — a fresh
install has none until you put a tree where wing can find it.

## Declaring a template

```lua
local wing = require("wing")

wing.template("go", {
  description = "Go CLI app with Makefile, flake.nix, tests, and release hooks",
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

-- add one that lives anywhere
wing.template("paper", { description = "a LaTeX paper", dir = "/home/me/templates/paper" })
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
