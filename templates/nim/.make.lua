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

---------------------------------------------------------------------------- nim

local ENTRY = "src/{{snake_name}}.nim"

-- Every Nim source this repository owns. Walked with find rather than globbed: `**` matches a
-- single directory level, so a glob would quietly miss anything nested deeper.
local function nim_files()
  local found = oslo.run{ "find", "src", "tests", "-type", "f", "-name", "*.nim",
                          capture = true }
  local files = {}
  for path in (found.out or ""):gmatch("[^\n]+") do files[#files + 1] = path end
  table.sort(files)
  return files
end

make.recipe{ name = "build", desc = "the binary",
             run = function() sh.nim("c", "-d:release", "--out:" .. NAME, ENTRY) end }
make.alias("b", "build")

make.recipe{
  name = "run",
  desc = "run it: bare words pass through, flags go in --args",
  deps = { "build" },
  params = { { "--args", desc = "a quoted argument string, for arguments starting with a dash" } },
  run = function(a)
    local argv = {}
    for _, word in ipairs(a.rest or {}) do argv[#argv + 1] = word end
    if type(a.args) == "string" then
      for word in a.args:gmatch("%S+") do argv[#argv + 1] = word end
    end
    sh["./" .. NAME](table.unpack(argv))
  end,
}
make.alias("r", "run")

make.recipe{ name = "test", desc = "the suite", run = function() sh.nimble("test", "-y") end }
make.alias("t", "test")

make.recipe{
  name = "test-all",
  desc = "the suite, plus a release compile check",
  deps = { "test" },
  run = function()
    sh.nim("c", "-d:release", "--out:/tmp/" .. NAME .. "-release-check", ENTRY)
    sh.rm("-f", "/tmp/" .. NAME .. "-release-check")
  end,
}

make.recipe{ name = "check", desc = "the semantic checks, without a binary",
             run = function() sh.nim("check", ENTRY) end }
make.alias("vet", "check")

make.recipe{ name = "fmt", desc = "format the sources",
             run = function() sh.nimpretty(table.unpack(nim_files())) end }

-- nimpretty rewrites in place and has no --check, so each file is formatted in a copy and compared.
make.recipe{
  name = "fmt-check",
  desc = "fail if anything is unformatted",
  run = function()
    local unformatted = {}
    for _, path in ipairs(nim_files()) do
      local scratch = "/tmp/" .. NAME .. "-nimpretty-" .. path:gsub("/", "-")
      sh.cp(path, scratch)
      sh.nimpretty(scratch)
      if not oslo.run{ "cmp", "-s", path, scratch }.ok then
        unformatted[#unformatted + 1] = path
      end
      sh.rm("-f", scratch)
    end
    assert(#unformatted == 0, "nimpretty needed on: " .. table.concat(unformatted, " "))
  end,
}

make.recipe{ name = "tidy", desc = "install the dependencies",
             run = function() sh.nimble("install", "-y", "--depsOnly") end }

make.recipe{
  name = "clean",
  desc = "remove every build output",
  run = function()
    sh.rm("-rf", NAME, "coverage.out", "bin", "nimcache")
    for _, path in ipairs(oslo.fs.glob("tests/test_*")) do
      if not path:match("%.nim$") then sh.rm("-f", path) end
    end
  end,
}

make.recipe{ name = "compile", desc = "clean, then build", deps = { "clean", "build" } }
make.alias("c", "compile")

make.recipe{
  name = "install",
  desc = "put the binary in $PREFIX/bin",
  deps = { "build" },
  run = function()
    sh.install("-d", PREFIX .. "/bin")
    sh.install("-m", "0755", NAME, PREFIX .. "/bin/" .. NAME)
    print("installed -> " .. PREFIX .. "/bin/" .. NAME)
  end,
}

make.recipe{ name = "uninstall", desc = "take it back out of $PREFIX/bin",
             run = function() sh.rm("-f", PREFIX .. "/bin/" .. NAME) end }

make.recipe{ name = "verify", desc = "the whole local gate",
             deps = { "fmt-check", "check", "test" } }
make.alias("v", "verify")
