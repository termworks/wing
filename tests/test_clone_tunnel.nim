import std/[os, osproc, strutils]

import test_support

compileBinary()

let envPrefix = freshEnv("clonetunnel")
let wing = wing(envPrefix)
discard checked(wing & "init")

let root = "/tmp/wing-clonetunnel"
resetDir(root)
let codeRoot = root / "code"
let withRoot = "WING_CODE_ROOT=" & quoteShell(codeRoot) & " "
let wingCode = wing(envPrefix & withRoot)

# --- a URL already says where a project belongs -------------------------------
# The layout is what lets two machines agree about a path without either being told.
let sshForm = checked(wingCode & "project clone git@github.com:owner/thing.git --dry-run")
doAssert sshForm.contains(codeRoot / "github.com" / "owner" / "thing"), sshForm
let httpsForm = checked(wingCode & "project clone https://gitlab.com/group/sub/app --dry-run")
doAssert httpsForm.contains(codeRoot / "gitlab.com" / "group" / "sub" / "app"), httpsForm
# `owner/name` is the form everybody types, and everybody means GitHub by it.
let shortForm = checked(wingCode & "project clone owner/thing --dry-run")
doAssert shortForm.contains("github.com/owner/thing"), shortForm
doAssert shortForm.contains("https://github.com/owner/thing.git"), shortForm
# A repository on this filesystem has no host or owner to file it under.
let localForm = checked(wingCode & "project clone file:///srv/git/repo.git --dry-run")
doAssert localForm.contains(codeRoot / "repo"), localForm
doAssert not localForm.contains("srv/git/repo/"), "a local path is not a directory tree"

# --- cloning for real, from a repository on this machine ----------------------
let origin = root / "origin.git"
doAssert execCmdEx("git init -q --bare " & quoteShell(origin)).exitCode == 0
let seed = root / "seed"
doAssert execCmdEx("git clone -q " & quoteShell(origin) & " " &
    quoteShell(seed)).exitCode == 0
writeFile(seed / "go.mod", "module thing\n")
for command in ["add -A", "-c user.email=t@t -c user.name=t commit -qm seed",
                "push -q origin HEAD"]:
  doAssert execCmdEx("git -C " & quoteShell(seed) & " " & command).exitCode ==
      0, command

let cloned = checked(wingCode & "project clone " & quoteShell("file://" & origin))
doAssert dirExists(codeRoot / "origin"), cloned
# Registered by the clone, with the language read off what arrived.
let listed = checked(wing & "project list --raw")
doAssert listed.contains("origin"), listed
doAssert listed.toLowerAscii().contains("go"), listed

# --- adopt registers a checkout that is already where it belongs --------------
let adopted = checked(wingCode & "project adopt " & quoteShell(seed) & " --in-place")
doAssert adopted.contains("registered"), adopted
doAssert checked(wing & "project list --raw").contains(seed)
# Twice is not an error: the same path on the same machine is the same project.
doAssert checked(wingCode & "project adopt " & quoteShell(seed) &
    " --in-place").contains("already registered")

# A directory with no origin cannot be filed anywhere, and says so.
let orphan = root / "orphan"
createDir(orphan)
let refused = run(wingCode & "project adopt " & quoteShell(orphan))
doAssert refused.code != 0
doAssert refused.output.contains("--in-place"), refused.output

# --- tunnels ------------------------------------------------------------------
discard checked(wing & "machine add lab 10.0.0.1:22:local --username tester")
doAssert checked(wing & "machine tunnel list").contains("No tunnels")

discard checked(wing & "machine tunnel add db lab --local 5433:localhost:5432")
let tunnels = checked(wing & "machine tunnel list")
doAssert tunnels.contains("5433:localhost:5432"), tunnels
doAssert tunnels.contains("down"), "a tunnel that was never started is down"

let duplicate = run(wing & "machine tunnel add db lab --local 1:localhost:2")
doAssert duplicate.code != 0
let noSpec = run(wing & "machine tunnel add other lab")
doAssert noSpec.code != 0
doAssert noSpec.output.contains("--local"), noSpec.output

doAssert run(wing & "machine tunnel stop db").code != 0,
    "stopping a tunnel that is down fails"
discard checked(wing & "machine tunnel remove db")
doAssert checked(wing & "machine tunnel list").contains("No tunnels")

# --- the ssh config every other tool reads ------------------------------------
let config = checked(wing & "machine ssh-config lab")
# The bare name is what makes `ssh lab`, `scp` and `git clone lab:...` work.
doAssert config.contains("Host lab\n"), config
doAssert config.contains("Host lab-local"), config
doAssert config.contains("HostName 10.0.0.1"), config
