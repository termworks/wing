import std/[os, osproc, strutils]

import test_support

compileBinary()

# These exercise the parts that do not need a reachable machine: selection by name and tag, the
# argument shapes, and the failure messages. Whether ssh works is ssh's business; whether wing aims
# the command at the right machines is this file's.
let envPrefix = freshEnv("machremote")
let wing = wing(envPrefix)
discard checked(wing & "init")

discard checked(wing & "machine add lab 10.0.0.1:22:local --username tester " &
    "--tag dev --tag gpu")
discard checked(wing & "machine add build 10.0.0.2:22:local --username tester --tag dev")
discard checked(wing & "machine add lonely 10.0.0.3:22:local --username tester")

# --- tags are stored, listed, and can be changed ------------------------------
let listed = checked(wing & "machine list")
doAssert listed.contains("dev, gpu"), listed
doAssert listed.contains("Tags"), listed

discard checked(wing & "machine tag lonely spare")
doAssert checked(wing & "machine list").contains("spare")
let untagged = checked(wing & "machine untag lab gpu")
doAssert not untagged.contains("gpu"), untagged
# Removing a tag a machine does not carry is not an error: the end state is what was asked for.
discard checked(wing & "machine untag lab gpu")

# --- a command has to name machines that exist --------------------------------
let noSuch = run(wing & "machine run nowhere -- true")
doAssert noSuch.code != 0
doAssert noSuch.output.contains("not found"), noSuch.output

let noTag = run(wing & "machine run --tag nosuchtag -- true")
doAssert noTag.code != 0
doAssert noTag.output.contains("nosuchtag"), noTag.output

# A selection without a command is a mistake worth naming, rather than an ssh session with no
# argument on every machine at once.
let noCommand = run(wing & "machine run --all")
doAssert noCommand.code != 0
doAssert noCommand.output.contains("COMMAND"), noCommand.output

# --- push and pull want a machine and a path ----------------------------------
let noColon = run(wing & "machine push /tmp/x lab/tmp/y")
doAssert noColon.code != 0
doAssert noColon.output.contains("NAME:/path"), noColon.output

let unknownTarget = run(wing & "machine push /tmp/x nowhere:/tmp/y")
doAssert unknownTarget.code != 0
doAssert unknownTarget.output.contains("not found"), unknownTarget.output

# --- facts are cached, so they can be read without reaching anything ----------
let factsHome = envPrefix.split("XDG_DATA_HOME=")[1].split(" ")[0].strip(
    chars = {'"', '\''})
let factsPath = factsHome / "wing" / "machine-facts.toml"
createDir(parentDir(factsPath))
writeFile(factsPath, """[[facts]]
machine = "lab"
os = "Debian GNU/Linux 13"
kernel = "6.1.0"
arch = "aarch64"
cpus = "8"
memory = "2Gi / 16Gi"
disk = "10G / 100G (10%)"
uptime = "up 3 days"
collected_at = "2026-08-24 10:00:00"
""")
let facts = checked(wing & "machine facts lab")
doAssert facts.contains("Debian GNU/Linux 13"), facts
doAssert facts.contains("aarch64"), facts
doAssert facts.contains("8"), facts

let factsRaw = checked(wing & "machine facts lab --raw")
doAssert factsRaw.contains("lab\tDebian GNU/Linux 13"), factsRaw
let factsJson = checked(wing & "machine facts lab --json")
doAssert factsJson.contains("\"arch\": \"aarch64\""), factsJson

# --- doctor reports on the setup and names the fix ----------------------------
let doctor = checked(wing & "doctor")
doAssert doctor.contains("data directory"), doctor
doAssert doctor.contains("template roots"), doctor
doAssert doctor.contains("machines"), doctor
# Something is always worth mentioning in a fresh environment; what matters is that a warning
# carries the command that answers it.
doAssert doctor.contains("→ ") or doctor.contains("Everything checks out"), doctor
