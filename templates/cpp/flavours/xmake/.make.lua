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

---------------------------------------------------------------------------- xmake

make.recipe{
  name = "config",
  desc = "configure the build: --toolchain clang | gcc",
  params = { { "--toolchain", desc = "clang or gcc; clang by default" } },
  run = function(a)
    local argv = { "config", "-y" }
    local chain = a.toolchain or TOOLCHAIN or "clang"
    if chain then argv[#argv + 1] = "--toolchain=" .. chain end
    sh.xmake(table.unpack(argv))
  end,
}

make.recipe{ name = "build", desc = "the library",
             run = function() sh.xmake("build", "-y") end }
make.alias("b", "build")

make.recipe{ name = "test", desc = "the suite", run = function() sh.xmake("test") end }
make.alias("t", "test")

make.recipe{
  name = "run",
  desc = "run a target: bare words name the target and its arguments",
  run = function(a) sh.xmake("run", table.unpack(a.rest or {})) end,
}
make.alias("r", "run")

make.recipe{ name = "install", desc = "install into $PREFIX", deps = { "build" },
             run = function() sh.xmake("install", "-o", PREFIX) end }

make.recipe{ name = "clean", desc = "remove the build outputs",
             run = function() sh.xmake("clean", "--all") end }

-------------------------------------------------------------------- static musl

-- What ships. A binary linked against the host libc stops working the moment it is copied to a
-- machine with a different one, so the release build targets musl and links statically.
--
-- The toolchain comes from the flake as a path (MUSL_CC), not from $PATH: musl headers on the
-- default search path make an ordinary build compile against musl and link against glibc, which
-- succeeds silently and crashes at startup.
--
-- gcc rather than clang here, and only here: musl-clang has no C++ standard library, so a clang
-- musl build works for C and falls over on the first #include <string>. `make config` still
-- defaults to clang, which is what the dev loop uses.
local function musl_cc()
  local root = os.getenv("MUSL_CC") or ""
  assert(root ~= "", "the static build needs MUSL_CC from the dev shell: nix develop")
  return root
end

-- Asked of the ELF, not assumed. "static" quietly coming out dynamic is only ever noticed by
-- whoever the binary fails for. `ldd` is not enough: it prints "statically linked" for a binary
-- that still carries an INTERP and will not start.
local function assert_static(path)
  local segments = oslo.run{ "readelf", "-l", path, capture = true }
  local dynamic = oslo.run{ "readelf", "-d", path, capture = true }
  assert(segments.ok, path .. " was not produced, or readelf could not read it")
  assert(not (segments.out or ""):find("program interpreter"),
         path .. " requests a dynamic loader; it is not static")
  assert(not (dynamic.out or ""):find("NEEDED"),
         path .. " has NEEDED entries; it is not static")
  print(oslo.ui.style("✓ static", { fg = "green" }) .. "  " .. path)
end

make.recipe{
  name = "static",
  desc = "a static musl build of everything, for shipping",
  run = function()
    local cc = musl_cc()
    sh.xmake("config", "-y", "-m", "release",
             "--cc=" .. cc .. "/bin/gcc",
             "--cxx=" .. cc .. "/bin/g++",
             "--ld=" .. cc .. "/bin/g++",
             "--ldflags=-static")
    sh.xmake("build", "-y", "--all")
    -- Walked with find, not globbed: oslo's `**` matches a single directory level and xmake nests
    -- its output under build/<plat>/<arch>/<mode>/, so a glob finds nothing and checks nothing.
    local found = oslo.run{ "find", "build", "-type", "f", "-name", "*_test", capture = true }
    local checked = 0
    for path in (found.out or ""):gmatch("[^\n]+") do
      assert_static(path)
      checked = checked + 1
    end
    assert(checked > 0, "no test binary was produced, so nothing was checked")
    -- Put the ordinary configuration back, so the next `make build` is the dev one again.
    sh.xmake("config", "-y", "--toolchain=clang")
  end,
}

make.recipe{ name = "compile", desc = "clean, then build", deps = { "clean", "build" } }
make.alias("c", "compile")

make.recipe{ name = "verify", desc = "the whole local gate", deps = { "fmt-check", "test" } }
make.alias("v", "verify")
