-- {{kebab_name}}'s build, as recipes. This replaced the Makefile; there is no other.
--
--   make            the recipes, with what each of them says it does
--   make build      the binary
--   make test       the suite
--   make verify     the whole local gate
--
-- At an oslo prompt in this directory `make` is enough; everywhere else it is `oslo make`.
-- CI has no oslo, so it calls the language's own tool -- nothing here is on the release path.

local make = oslo.make

-- Name and version live in PROJECT, one per line, so every tool reads them from one place.
local function project()
  local found = {}
  for line in (oslo.fs.read("PROJECT") or ""):gmatch("[^\n]+") do
    local value = line:match("^%s*([^#%[%s]%S*)%s*$")
    if value then found[#found + 1] = value end
  end
  return found[1] or "{{kebab_name}}", found[2] or "0.1.0"
end

local NAME, VERSION = project()
local PREFIX = os.getenv("PREFIX") or (os.getenv("HOME") .. "/.local")

make.recipe{ name = "version", desc = "what this checkout calls itself",
             run = function() print(("%s v%s"):format(NAME, VERSION)) end }

local function need(tool, why)
  assert(oslo.run{ "sh", "-c", "command -v " .. tool, capture = true }.ok, why)
end

make.recipe{
  name = "release",
  desc = "cut a version: --type patch | minor | major | M.m.p",
  params = { { "--type", desc = "patch | minor | major | M.m.p" } },
  run = function(a)
    need("git-rel", "git-rel is not installed; install it first")
    assert(type(a.type) == "string",
           "which release? make release --type patch|minor|major|M.m.p")
    sh.git("rel", a.type)
  end,
}

make.recipe{
  name = "changelog",
  desc = "regenerate CHANGELOG.md",
  run = function()
    need("git-cliff", "git-cliff is not installed; install it first")
    sh.git("cliff", "-o", "CHANGELOG.md")
  end,
}

---------------------------------------------------------------------------- rust

local EXAMPLE = os.getenv("EXAMPLE") or "main"

make.recipe{ name = "build", desc = "the library",
             run = function() sh.cargo("build", "--lib") end }
make.alias("b", "build")

make.recipe{
  name = "run",
  desc = "run a development example: --example NAME",
  params = { { "--example", desc = "which example to run", default = EXAMPLE } },
  run = function(a) sh.cargo("run", "--example", a.example or EXAMPLE) end,
}
make.alias("r", "run")

make.recipe{ name = "test", desc = "the suite",
             run = function() sh.cargo("test", "--all-targets") end }
make.alias("t", "test")

make.recipe{ name = "test-all", desc = "the suite, with every feature on",
             run = function() sh.cargo("test", "--all-targets", "--all-features") end }

make.recipe{ name = "check", desc = "type-check every target",
             run = function() sh.cargo("check", "--all-targets") end }

make.recipe{ name = "check-all", desc = "type-check every target, every feature",
             run = function() sh.cargo("check", "--all-targets", "--all-features") end }

make.recipe{ name = "clippy", desc = "clippy, with warnings denied",
             run = function()
               sh.cargo("clippy", "--all-targets", "--all-features", "--", "-Dwarnings")
             end }

make.recipe{
  name = "rustdoc",
  desc = "build the docs, with warnings denied",
  run = function()
    local built = oslo.run{ "env", "RUSTDOCFLAGS=-Dwarnings",
                            "cargo", "doc", "--all-features", "--no-deps" }
    assert(built.ok, "rustdoc failed")
  end,
}

make.recipe{ name = "fmt", desc = "format the workspace",
             run = function() sh.cargo("fmt", "--all") end }

make.recipe{ name = "fmt-check", desc = "fail if anything is unformatted",
             run = function() sh.cargo("fmt", "--all", "--", "--check") end }

make.recipe{ name = "clean", desc = "remove every build output",
             run = function() sh.cargo("clean") end }

make.recipe{ name = "compile", desc = "clean, then build", deps = { "clean", "build" } }
make.alias("c", "compile")

make.recipe{
  name = "verify",
  desc = "the whole local gate",
  deps = { "fmt-check", "check", "test", "check-all", "test-all", "clippy", "rustdoc" },
}
make.alias("v", "verify")
