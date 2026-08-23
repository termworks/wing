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

------------------------------------------------------------ python (micromamba)

local ENV_PREFIX = os.getenv("ENV_PREFIX") or "./.micromamba"

local function run_py(...)
  sh.micromamba("run", "--prefix", ENV_PREFIX, "python", ...)
end
local function run_tool(tool, ...)
  sh.micromamba("run", "--prefix", ENV_PREFIX, tool, ...)
end

-- `env update` creates the prefix when it is missing and reconciles it when it is not, so one
-- command covers both and re-running setup is safe.
make.recipe{
  name = "setup",
  desc = "create and sync the local .micromamba environment",
  run = function()
    sh.micromamba("env", "update", "--yes", "--prefix", ENV_PREFIX,
                  "--file", "environment.yml")
  end,
}

make.recipe{ name = "build", desc = "the wheel and sdist into dist/",
             deps = { "setup" },
             run = function() sh.rm("-rf", "dist"); run_py("-m", "build", "--no-isolation", "--outdir", "dist") end }
make.alias("b", "build")

make.recipe{
  name = "run",
  desc = "run it: bare words pass through, flags go in --args",
  deps = { "setup" },
  params = { { "--args", desc = "a quoted argument string, for arguments starting with a dash" } },
  run = function(a)
    local argv = { "-m", "{{snake_name}}" }
    for _, word in ipairs(a.rest or {}) do argv[#argv + 1] = word end
    if type(a.args) == "string" then
      for word in a.args:gmatch("%S+") do argv[#argv + 1] = word end
    end
    run_py(table.unpack(argv))
  end,
}
make.alias("r", "run")

make.recipe{ name = "test", desc = "the suite", deps = { "setup" },
             run = function() run_tool("pytest") end }
make.alias("t", "test")

make.recipe{ name = "fmt", desc = "format and fix the sources", deps = { "setup" },
             run = function() run_tool("ruff", "format", "."); run_tool("ruff", "check", "--fix", ".") end }

make.recipe{ name = "fmt-check", desc = "fail if anything is unformatted", deps = { "setup" },
             run = function() run_tool("ruff", "format", "--check", "."); run_tool("ruff", "check", ".") end }
make.alias("check", "fmt-check")

make.recipe{ name = "clean", desc = "remove every build output",
             run = function()
               sh.rm("-rf", "dist", "build", ".pytest_cache", ".ruff_cache")
               for _, path in ipairs(oslo.fs.glob("src/*.egg-info")) do sh.rm("-rf", path) end
             end }

make.recipe{ name = "compile", desc = "clean, then build", deps = { "clean", "build" } }
make.alias("c", "compile")

make.recipe{ name = "verify", desc = "the whole local gate", deps = { "fmt-check", "test" } }
make.alias("v", "verify")
