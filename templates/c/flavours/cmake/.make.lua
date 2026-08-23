-- {{kebab_name}}'s tasks. This is not the build system -- {{builtin_flavour}} is. These recipes
-- only drive it, so anything about how this project compiles (standard, warnings, targets,
-- packages) belongs in the build file, and anything about how you drive it belongs here.
--
--   make            the recipes, with what each of them says it does
--   make config     configure the build tree: --toolchain clang | gcc
--   make build      the library
--   make test       the suite
--
-- At an oslo prompt in this directory `make` is enough; everywhere else it is `oslo make`.
-- CI has no oslo, so it calls the build system directly -- the same commands these recipes run.

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
local TOOLCHAIN = os.getenv("TOOLCHAIN")

make.recipe{ name = "version", desc = "what this checkout calls itself",
             run = function() print(("%s v%s"):format(NAME, VERSION)) end }

local function need(tool, why)
  assert(oslo.run{ "sh", "-c", "command -v " .. tool, capture = true }.ok, why)
end

-- Sources this project owns, which is what clang-format is pointed at. The formatter is not the
-- build system's job in either flavour, so it lives here in both.
local function sources()
  local found = oslo.run{ "find", "src", "include", "test", "-type", "f",
                          "(", "-name", "*.c", "-o", "-name", "*.h",
                          "-o", "-name", "*.cpp", "-o", "-name", "*.hpp", ")",
                          capture = true }
  local files = {}
  for path in (found.out or ""):gmatch("[^\n]+") do files[#files + 1] = path end
  table.sort(files)
  return files
end

make.recipe{ name = "fmt", desc = "format the sources",
             run = function() sh["clang-format"]("-i", table.unpack(sources())) end }

make.recipe{ name = "fmt-check", desc = "fail if anything is unformatted",
             run = function()
               sh["clang-format"]("--dry-run", "--Werror", table.unpack(sources()))
             end }

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

---------------------------------------------------------------------------- cmake

local BUILD_DIR = os.getenv("BUILD_DIR") or "build"

make.recipe{
  name = "config",
  desc = "configure the build tree: --toolchain clang | gcc",
  params = { { "--toolchain", desc = "clang or gcc; the default is whatever cmake finds" } },
  run = function(a)
    local argv = { "-S", ".", "-B", BUILD_DIR, "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON" }
    local chain = a.toolchain or TOOLCHAIN
    if chain == "clang" then
      argv[#argv + 1] = "-DCMAKE_C_COMPILER=clang"
      argv[#argv + 1] = "-DCMAKE_CXX_COMPILER=clang++"
    elseif chain == "gcc" then
      argv[#argv + 1] = "-DCMAKE_C_COMPILER=gcc"
      argv[#argv + 1] = "-DCMAKE_CXX_COMPILER=g++"
    end
    -- Ninja when it is here, so an incremental build is not a full one.
    if oslo.run{ "sh", "-c", "command -v ninja", capture = true }.ok then
      argv[#argv + 1] = "-GNinja"
    end
    sh.cmake(table.unpack(argv))
  end,
}

local function configured()
  if not oslo.fs.stat(BUILD_DIR) then make.run("config") end
end

make.recipe{ name = "build", desc = "the library",
             run = function() configured(); sh.cmake("--build", BUILD_DIR, "--parallel") end }
make.alias("b", "build")

make.recipe{
  name = "test",
  desc = "the suite",
  run = function()
    configured()
    sh.cmake("--build", BUILD_DIR, "--parallel")
    sh.ctest("--test-dir", BUILD_DIR, "--output-on-failure")
  end,
}
make.alias("t", "test")

make.recipe{ name = "install", desc = "install into $PREFIX", deps = { "build" },
             run = function() sh.cmake("--install", BUILD_DIR, "--prefix", PREFIX) end }

make.recipe{ name = "clean", desc = "remove the build tree",
             run = function() sh.rm("-rf", BUILD_DIR) end }

make.recipe{ name = "compile", desc = "clean, then build", deps = { "clean", "build" } }
make.alias("c", "compile")

make.recipe{ name = "verify", desc = "the whole local gate", deps = { "fmt-check", "test" } }
make.alias("v", "verify")
