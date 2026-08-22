-- wing's build, as recipes. This file replaced the Makefile; there is no other.
--
--   make                 the recipes, with what each of them says it does
--   make build           the release binary
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
local function nim_files()
  local files = {}
  for _, dir in ipairs({ "src", "tests" }) do
    for _, path in ipairs(oslo.fs.glob(dir .. "/**/*.nim")) do files[#files + 1] = path end
  end
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

local function report()
  local stat = oslo.fs.stat(BIN)
  if not stat then return end
  local megabytes = ("%.2f MB"):format(stat.size / 1048576)

  print("")
  print(oslo.ui.title(("%s %s   %s"):format(NAME, VERSION, megabytes)))
  line("binary", BIN)
  -- Bytes beside megabytes: `1.10 MB` cannot be subtracted from last week's `1.08 MB` to get one.
  line("size", megabytes .. dim("   " .. grouped(stat.size) .. " bytes"))
  print("")
end

---------------------------------------------------------------------------- building

make.recipe{ name = "version", desc = "what this checkout calls itself",
             run = function() print(("%s v%s"):format(NAME, VERSION)) end }

make.recipe{
  name = "build",
  desc = "the release binary",
  run = function()
    sh.nim("c", "-d:release", "--out:" .. BIN, ENTRY)
    report()
  end,
}

make.alias("b", "build")

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
