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

---------------------------------------------------------------------------- c++

local BUILD_DIR = os.getenv("BUILD_DIR") or "build"
local TARGET = "{{NAME}}"

-- Every C++ source this project owns, which is what clang-format is pointed at.
local function sources()
  local found = oslo.run{ "find", "src", "include", "test", "-type", "f",
                          "(", "-name", "*.cpp", "-o", "-name", "*.hpp",
                          "-o", "-name", "*.h", ")", capture = true }
  local files = {}
  for path in (found.out or ""):gmatch("[^\n]+") do files[#files + 1] = path end
  table.sort(files)
  return files
end

make.recipe{
  name = "config",
  desc = "run cmake into the build directory",
  run = function()
    sh.mkdir("-p", BUILD_DIR)
    sh.cmake("-S", ".", "-B", BUILD_DIR, "-Wno-dev",
             "-D" .. TARGET .. "_ENABLE_TESTS=ON",
             "-D" .. TARGET .. "_BUILD_EXAMPLES=ON")
  end,
}

make.recipe{
  name = "build",
  desc = "the library",
  run = function()
    if not oslo.fs.stat(BUILD_DIR) then make.run("config") end
    sh.cmake("--build", BUILD_DIR, "--parallel")
  end,
}
make.alias("b", "build")

make.recipe{
  name = "test",
  desc = "the suite",
  run = function()
    if not oslo.fs.stat(BUILD_DIR) then make.run("config") end
    sh.ctest("--test-dir", BUILD_DIR, "--output-on-failure")
  end,
}
make.alias("t", "test")

make.recipe{ name = "fmt", desc = "format the sources",
             run = function() sh["clang-format"]("-i", table.unpack(sources())) end }

make.recipe{ name = "fmt-check", desc = "fail if anything is unformatted",
             run = function()
               sh["clang-format"]("--dry-run", "--Werror", table.unpack(sources()))
             end }

make.recipe{ name = "clean", desc = "remove every build output",
             run = function() sh.rm("-rf", BUILD_DIR) end }

make.recipe{ name = "compile", desc = "clean, then build", deps = { "clean", "build" } }
make.alias("c", "compile")

make.recipe{ name = "verify", desc = "the whole local gate",
             deps = { "fmt-check", "build", "test" } }
make.alias("v", "verify")
