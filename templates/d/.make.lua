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

------------------------------------------------------------------------------ d

-- dub is the build system; these recipes only drive it. What this project depends on and how it is
-- configured lives in dub.json.
--
-- The compiler is a choice, not a flavour: ldc2, dmd and gdc all build the same dub project.
local COMPILER = os.getenv("DC") or "ldc2"

local function compiler(a)
  return a and a.compiler or COMPILER
end

local COMPILER_PARAM = { "--compiler", desc = "ldc2, dmd or gdc" }

make.recipe{
  name = "build",
  desc = "the binary: --compiler ldc2 | dmd | gdc",
  params = { COMPILER_PARAM },
  run = function(a) sh.dub("build", "--compiler=" .. compiler(a), "--build=release") end,
}
make.alias("b", "build")

make.recipe{
  name = "run",
  desc = "run it: bare words pass through, flags go in --args",
  params = { COMPILER_PARAM,
             { "--args", desc = "a quoted argument string, for arguments starting with a dash" } },
  run = function(a)
    local argv = { "run", "--compiler=" .. compiler(a), "--build=debug", "--" }
    for _, word in ipairs(a.rest or {}) do argv[#argv + 1] = word end
    if type(a.args) == "string" then
      for word in a.args:gmatch("%S+") do argv[#argv + 1] = word end
    end
    sh.dub(table.unpack(argv))
  end,
}
make.alias("r", "run")

make.recipe{
  name = "test",
  desc = "the unittests: --compiler ldc2 | dmd | gdc",
  params = { COMPILER_PARAM },
  run = function(a) sh.dub("test", "--compiler=" .. compiler(a)) end,
}
make.alias("t", "test")

make.recipe{
  name = "cover",
  desc = "the unittests, with coverage written to *.lst",
  params = { COMPILER_PARAM },
  run = function(a)
    sh.dub("test", "--compiler=" .. compiler(a), "--build=unittest-cov")
  end,
}

-- Sources this project owns, which is what the formatter and the linter are pointed at.
local function sources()
  local found = oslo.run{ "find", "source", "-type", "f", "-name", "*.d", capture = true }
  local files = {}
  for path in (found.out or ""):gmatch("[^\n]+") do files[#files + 1] = path end
  table.sort(files)
  return files
end

make.recipe{ name = "fmt", desc = "format the source",
             run = function() sh.dfmt("--inplace", table.unpack(sources())) end }

-- dfmt has no check mode, so each file is formatted in a copy and compared.
make.recipe{
  name = "fmt-check",
  desc = "fail if anything is unformatted",
  run = function()
    local unformatted = {}
    for _, path in ipairs(sources()) do
      local scratch = "/tmp/" .. NAME .. "-dfmt-" .. path:gsub("/", "-")
      sh.cp(path, scratch)
      sh.dfmt("--inplace", scratch)
      if not oslo.run{ "cmp", "-s", path, scratch }.ok then
        unformatted[#unformatted + 1] = path
      end
      sh.rm("-f", scratch)
    end
    assert(#unformatted == 0, "dfmt needed on: " .. table.concat(unformatted, " "))
  end,
}

make.recipe{ name = "check", desc = "lint the source",
             run = function() sh.dscanner("--styleCheck", "source") end }
make.alias("vet", "check")

make.recipe{
  name = "clean",
  desc = "remove every build output",
  run = function()
    sh.dub("clean")
    sh.rm("-rf", NAME, ".dub")
    for _, path in ipairs(oslo.fs.glob("*.lst")) do sh.rm("-f", path) end
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
