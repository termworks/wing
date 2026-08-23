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

---------------------------------------------------------------------------- zig

local OPTIMIZE = os.getenv("OPTIMIZE") or "ReleaseSafe"

make.recipe{ name = "build", desc = "the binary",
             run = function() sh.zig("build", "-Doptimize=" .. OPTIMIZE) end }
make.alias("b", "build")

make.recipe{
  name = "run",
  desc = "run it: bare words pass through, flags go in --args",
  params = { { "--args", desc = "a quoted argument string, for arguments starting with a dash" } },
  run = function(a)
    local argv = { "build", "run", "--" }
    for _, word in ipairs(a.rest or {}) do argv[#argv + 1] = word end
    if type(a.args) == "string" then
      for word in a.args:gmatch("%S+") do argv[#argv + 1] = word end
    end
    sh.zig(table.unpack(argv))
  end,
}
make.alias("r", "run")

make.recipe{ name = "test", desc = "the suite",
             run = function() sh.zig("build", "test", "-Doptimize=" .. OPTIMIZE) end }
make.alias("t", "test")

make.recipe{ name = "check", desc = "compile the tests without optimising",
             run = function() sh.zig("build", "test") end }
make.alias("vet", "check")

make.recipe{ name = "fmt", desc = "format the sources",
             run = function() sh.zig("fmt", "build.zig", "src") end }

make.recipe{ name = "fmt-check", desc = "fail if anything is unformatted",
             run = function() sh.zig("fmt", "--check", "build.zig", "src") end }

make.recipe{ name = "tidy", desc = "fetch the declared dependencies",
             run = function() sh.zig("build", "--fetch") end }

make.recipe{ name = "clean", desc = "remove every build output",
             run = function() sh.rm("-rf", "zig-out", ".zig-cache", NAME) end }

make.recipe{ name = "compile", desc = "clean, then build", deps = { "clean", "build" } }
make.alias("c", "compile")

make.recipe{
  name = "install",
  desc = "put the binary in $PREFIX/bin",
  deps = { "build" },
  run = function()
    sh.install("-d", PREFIX .. "/bin")
    sh.install("-m", "0755", "zig-out/bin/" .. NAME, PREFIX .. "/bin/" .. NAME)
    print("installed -> " .. PREFIX .. "/bin/" .. NAME)
  end,
}

make.recipe{ name = "uninstall", desc = "take it back out of $PREFIX/bin",
             run = function() sh.rm("-f", PREFIX .. "/bin/" .. NAME) end }

make.recipe{ name = "verify", desc = "the whole local gate", deps = { "fmt-check", "test" } }
make.alias("v", "verify")
