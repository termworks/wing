-- wing's build, as recipes. This file replaced the Makefile; there is no other.
--
--   make                 the recipes, with what each of them says it does
--   make build           the shipping binary: static musl, runs anywhere
--   make test            the suite
--   make install         the binary, into $PREFIX/bin
--   make verify          the whole local gate
--
-- At an oslo prompt in this directory `make` is enough; everywhere else it is `oslo make`.
--
-- CI has no oslo, so it runs nimble directly -- nothing here is on the release path.

local make = oslo.make

---------------------------------------------------------------------------- what the build is

-- One place holds the version: the nimble file, which nimble reads too.
local VERSION = oslo.fs.read("wing.nimble"):match('version%s*=%s*"([%d%.]+)"')
assert(VERSION, "wing.nimble is missing its version line")

local NAME = "wing"
local BIN = "wing"
local ENTRY = "src/wing.nim"
local PREFIX = os.getenv("PREFIX") or (os.getenv("HOME") .. "/.local")

-- Every Nim source this repository owns, which is what the formatter is pointed at.
--
-- Walked with find, not globbed: oslo's `**` matches a single directory level, so `src/**/*.nim`
-- silently covered 16 of the 52 files and the formatter gate passed on code it had never read.
local function nim_files()
  local found = oslo.run{ "find", "src", "tests", "-type", "f", "-name", "*.nim",
                          capture = true }
  assert(found.ok, "could not list the Nim sources")
  local files = {}
  for path in (found.out or ""):gmatch("[^\n]+") do files[#files + 1] = path end
  table.sort(files)
  return files
end

---------------------------------------------------------------------------- saying what was built

local function dim(text)
  return oslo.ui.style(text, { dim = true })
end

local function line(label, value)
  print(dim(oslo.ui.pad(label, 8)) .. value)
end

-- `1155592` -> `1,155,592`. A number this long is read in groups or not at all.
local function grouped(n)
  local text = tostring(math.floor(n))
  local out = text:sub(-3)
  local at = #text - 3
  while at > 0 do
    out = text:sub(math.max(1, at - 2), at) .. "," .. out
    at = at - 3
  end
  return out
end

-- Asked of the ELF, not assumed. wing has two builds and only one of them ships, so a report that
-- always claimed "static" would be wrong half the time -- and that is the half nobody notices
-- until the binary is on a machine with a different libc.
local function linkage(path)
  local segments = oslo.run{ "readelf", "-l", path, capture = true }
  local dynamic = oslo.run{ "readelf", "-d", path, capture = true }
  if not segments.ok then return nil end
  if (segments.out or ""):find("program interpreter") or (dynamic.out or ""):find("NEEDED") then
    return "dynamic"
  end
  return "static"
end

local function report()
  local stat = oslo.fs.stat(BIN)
  if not stat then return end
  local megabytes = ("%.2f MB"):format(stat.size / 1048576)

  print("")
  print(oslo.ui.title(("%s %s   %s"):format(NAME, VERSION, megabytes)))
  line("binary", BIN)
  -- Bytes beside megabytes: `1.10 MB` cannot be subtracted from last week's `1.08 MB` to get one.
  line("size", megabytes .. dim("   " .. grouped(stat.size) .. " bytes"))

  local kind = linkage(BIN)
  if kind == "static" then
    line("linking", oslo.ui.style("✓ static", { fg = "green" }) ..
                    dim("   no runtime dependencies"))
  elseif kind == "dynamic" then
    line("linking", oslo.ui.style("dynamic", { fg = "yellow" }) ..
                    dim("   make build for the one that ships"))
  end
  print("")
end

---------------------------------------------------------------------------- building

make.recipe{ name = "version", desc = "what this checkout calls itself",
             run = function() print(("%s v%s"):format(NAME, VERSION)) end }

-- musl and its Lua are deliberately NOT on the dev shell's search path: headers there make an
-- ordinary `nim c` compile against musl and link against glibc, which builds without a word and
-- then segfaults. The flake exports them as paths instead (see its buildEnv), and only this build
-- is given them.
--
-- WING_LUA goes through `env` rather than the recipe's own environment so it reaches this compile
-- and nothing after it: a test compiled against musl's Lua and linked to glibc is that same bug.
local function nim_musl()
  local musl = os.getenv("MUSL_DEV") or ""
  local lua = os.getenv("LUA_MUSL") or ""
  assert(musl ~= "" and lua ~= "",
         "the static build needs MUSL_DEV and LUA_MUSL from the dev shell: nix develop .#ci")
  -- `oslo.run` rather than `sh.env`: oslo answers some commands in rows instead of running them,
  -- and `env` is one of them -- so `sh.env(...)` returned happily having compiled nothing.
  local built = oslo.run{ "env", "WING_LUA=" .. lua, "nim", "c", "-d:release",
                          "--gcc.exe:" .. musl .. "/bin/musl-gcc",
                          "--gcc.linkerexe:" .. musl .. "/bin/musl-gcc",
                          "--passL:-static",
                          "--out:" .. BIN, ENTRY }
  assert(built.ok, "the static build failed")
end

-- The one that gets installed and shipped, and what `make build` means. It refuses to finish
-- unless the result really is static: "static" quietly coming out dynamic is only ever noticed by
-- whoever the binary fails for, on the musl box it was built to run on.
make.recipe{
  name = "release-musl",
  desc = "a static binary that needs nothing on the target machine",
  run = function()
    nim_musl()
    local kind = linkage(BIN)
    assert(kind ~= nil, BIN .. " was not produced, or readelf could not read it")
    assert(kind == "static", BIN .. " came out dynamic; it must not ship")
    report()
  end,
}

make.recipe{ name = "build", desc = "the shipping binary (static musl)",
             deps = { "release-musl" } }

make.alias("b", "build")

-- Against the host libc, for when the edit-compile loop matters more than portability. Not what
-- install or the release uses.
make.recipe{
  name = "build-gnu",
  desc = "a dynamic binary against the host libc, for iterating",
  run = function()
    sh.nim("c", "-d:release", "--out:" .. BIN, ENTRY)
    report()
  end,
}

-- Bare words reach the binary as they are written; anything with a leading dash goes in --args,
-- because make parses a flag before the recipe ever sees it.
--
--   make run project list
--   make run --args="--help"
--
-- The `=` is not optional there: `--args --help` hands make two flags, and the recipe never sees
-- the second one.
make.recipe{
  name = "run",
  desc = "run it: bare words pass through, flags go in --args",
  deps = { "build" },
  params = { { "--args", desc = "a quoted argument string, for arguments that start with a dash" } },
  run = function(a)
    local argv = {}
    for _, word in ipairs(a.rest or {}) do argv[#argv + 1] = word end
    if type(a.args) == "string" then
      for word in a.args:gmatch("%S+") do argv[#argv + 1] = word end
    end
    sh["./" .. BIN](table.unpack(argv))
  end,
}

make.alias("r", "run")

make.recipe{
  name = "clean",
  desc = "remove every build output",
  run = function()
    sh.rm("-rf", BIN, "bin", "nimcache", "coverage.out")
    -- The compiled test binaries nim leaves beside their sources.
    for _, path in ipairs(oslo.fs.glob("tests/test_*")) do
      if not path:match("%.nim$") then sh.rm("-f", path) end
    end
  end,
}

make.recipe{ name = "compile", desc = "clean, then build", deps = { "clean", "build" } }
make.alias("c", "compile")

---------------------------------------------------------------------------- checking

make.recipe{
  name = "test",
  desc = "the suite",
  run = function() sh.nimble("test", "-y") end,
}

make.alias("t", "test")

make.recipe{
  name = "test-all",
  desc = "the suite, plus a release compile check",
  deps = { "test" },
  run = function()
    sh.nim("c", "-d:release", "--out:/tmp/wing-release-check", ENTRY)
    sh.rm("-f", "/tmp/wing-release-check")
  end,
}

make.recipe{
  name = "check",
  desc = "the Nim semantic checks, without producing a binary",
  run = function() sh.nim("check", ENTRY) end,
}

make.alias("vet", "check")

make.recipe{
  name = "fmt",
  desc = "format the Nim sources",
  run = function() sh.nimpretty(table.unpack(nim_files())) end,
}

-- nimpretty rewrites in place and has no --check, so each file is formatted in a copy and compared.
make.recipe{
  name = "fmt-check",
  desc = "fail if anything is unformatted",
  run = function()
    local unformatted = {}
    for _, path in ipairs(nim_files()) do
      local scratch = "/tmp/wing-nimpretty-" .. path:gsub("/", "-")
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

make.recipe{
  name = "verify",
  desc = "the whole local gate",
  deps = { "fmt-check", "check", "test" },
}

make.alias("v", "verify")

---------------------------------------------------------------------------- shipping

make.recipe{
  name = "tidy",
  desc = "install the Nim dependencies",
  run = function() sh.nimble("install", "-y", "--depsOnly") end,
}

make.recipe{
  name = "install",
  desc = "put the binary in $PREFIX/bin",
  deps = { "build" },
  run = function()
    local dest = (os.getenv("DESTDIR") or "") .. PREFIX .. "/bin"
    sh.install("-d", dest)
    sh.install("-m", "0755", BIN, dest .. "/" .. NAME)
    print(oslo.ui.style("✓ ", { fg = "green" }) .. dest .. "/" .. NAME)
  end,
}

make.recipe{
  name = "uninstall",
  desc = "take it back out of $PREFIX/bin",
  run = function() sh.rm("-f", PREFIX .. "/bin/" .. NAME) end,
}

make.recipe{
  name = "changelog",
  desc = "regenerate CHANGELOG.md",
  run = function()
    assert(oslo.run{ "sh", "-c", "command -v git-cliff", capture = true }.ok,
           "git-cliff is not installed; install it first")
    sh.git("cliff", "-o", "CHANGELOG.md")
  end,
}

make.recipe{
  name = "mdbook",
  desc = "build the book into ../docs",
  run = function()
    sh.mdbook("build", "book", "--dest-dir", "../docs")
    sh.git("add", "-A")
    sh.git("commit", "-m", "docs: building website/mdbook")
  end,
}

make.recipe{
  name = "release",
  desc = "cut a version: --type patch | minor | major | M.m.p",
  params = { { "--type", desc = "patch | minor | major | M.m.p" } },
  run = function(a)
    assert(oslo.run{ "sh", "-c", "command -v git-rel", capture = true }.ok,
           "git-rel is not installed; install it first")
    assert(type(a.type) == "string",
           "which release? make release --type patch|minor|major|M.m.p")
    sh.git("rel", a.type)
  end,
}
