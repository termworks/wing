import std/[os, strutils]

import test_support

compileBinary()

let envPrefix = freshEnv("env")
let wing = wing(envPrefix)
let proj = "/tmp/wing-env-proj"
resetDir(proj)
createDir(proj / "bin")
writeFile(proj / ".envrc", "export FOO=bar\nexport PATH=$PWD/bin:$PATH\n")

# Where the unload leg lands. Its own .envrc is left un-allowed on purpose: leaving a project
# must unload it either way, whether the new directory has no .envrc or one that is refused.
let outside = "/tmp/wing-env-outside"
resetDir(outside)
writeFile(outside / ".envrc", "export OUTSIDE=nope\n")

# --- allow gate -------------------------------------------------------------
# Before authorization, export must refuse and emit nothing.
let blocked = run("cd " & quoteShell(proj) & " && WING_DIFF='' " & wing &
    "env export bash 2>/dev/null")
doAssert blocked.code != 0, "export should refuse un-allowed .envrc"
doAssert blocked.output.strip().len == 0, "refused export must emit nothing"

# Authorize.
discard checked(wing & "env allow " & quoteShell(proj))
let allowState = checked("cd " & quoteShell(proj) & " && " & wing & "env status")
doAssert allowState.contains("allowed:  yes")

# Deny revokes authorization.
discard checked(wing & "env deny " & quoteShell(proj))
let reblocked = run("cd " & quoteShell(proj) & " && WING_DIFF='' " & wing &
    "env export bash 2>/dev/null")
doAssert reblocked.code != 0
discard checked(wing & "env allow " & quoteShell(proj))

# --- hook output ------------------------------------------------------------
let hookBash = checked(wing & "env hook bash")
doAssert hookBash.contains("__wing_env_hook")
doAssert hookBash.contains("PROMPT_COMMAND")
let hookFish = checked(wing & "env hook fish")
doAssert hookFish.contains("--on-variable PWD")

# --- core invariant: load across 3 cycles, PATH must not accumulate ---------
# Simulates a real shell: each cycle evals the emitted diff (which carries
# WING_DIFF forward), then we count how many times the project bin appears.
let harness = """
set +e
cd '__PROJ__'
WING_DIFF=''
eval "$(__WING__ env export bash 2>/dev/null)"
eval "$(__WING__ env export bash 2>/dev/null)"
eval "$(__WING__ env export bash 2>/dev/null)"
BINS=$(echo "$PATH" | tr ':' '\n' | grep -c 'wing-env-proj/bin')
echo "CYCLES bins=$BINS foo=$FOO"
cd '__OUTSIDE__'
eval "$(__WING__ env export bash 2>/dev/null)"
echo "UNLOAD foo=${FOO:-unset} outside=${OUTSIDE:-unset} bins=$(echo "$PATH" | tr ':' '\n' | grep -c 'wing-env-proj/bin')"
"""
let script = harness.replace("__PROJ__", proj).replace("__OUTSIDE__",
    outside).replace("__WING__", quoteShell(Binary))
let cycleRes = run(envPrefix & "bash -c " & quoteShell(script))
doAssert cycleRes.code == 0, cycleRes.output
let accMsg = "PATH accumulated across cycles: " & cycleRes.output
doAssert cycleRes.output.contains("bins=1"), accMsg
doAssert cycleRes.output.contains("foo=bar"), cycleRes.output
let unloadMsg = "unload did not clear FOO: " & cycleRes.output
doAssert cycleRes.output.contains("UNLOAD foo=unset"), unloadMsg
doAssert cycleRes.output.contains("bins=0"), "unload left the project bin on PATH: " &
    cycleRes.output
# The blocked .envrc must not have been applied while unloading the previous one.
doAssert cycleRes.output.contains("outside=unset"), "blocked .envrc was applied: " &
    cycleRes.output

# --- json export parses -----------------------------------------------------
let jsonOut = run("cd " & quoteShell(proj) & " && WING_DIFF='' " & wing &
    "env export json 2>/dev/null")
doAssert jsonOut.code == 0, jsonOut.output
doAssert jsonOut.output.contains("\"up\""), jsonOut.output
doAssert jsonOut.output.contains("\"down\""), jsonOut.output

# --- envrc in a parent dir resolves from a child ----------------------------
createDir(proj / "sub" / "deep")
let parentRes = run("cd " & quoteShell(proj / "sub" / "deep") &
    " && WING_DIFF='' " & wing & "env export bash 2>/dev/null")
doAssert parentRes.code == 0, parentRes.output
let parentMsg = "envrc should resolve from child dir: " & parentRes.output
doAssert parentRes.output.contains("FOO"), parentMsg
