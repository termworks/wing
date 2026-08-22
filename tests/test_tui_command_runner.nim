import std/[os, strutils]

import test_support

compileBinary()

let envPrefix = freshEnv("tui-command")
let wing = wing(envPrefix)

let emptySnapshot = checked(wing & "tui --snapshot")
doAssert emptySnapshot.contains("wing tui")
doAssert emptySnapshot.contains("Projects:")

discard checked(wing & "tui --command " &
    quoteShell("project add tui_demo --path /tmp/tui_demo --language go"))

let populatedSnapshot = checked(wing & "tui --snapshot")
doAssert populatedSnapshot.contains("Projects: 1")

let blockedNested = run(wing & "tui --command " & quoteShell("tui --snapshot"))
doAssert blockedNested.code != 0
doAssert blockedNested.output.contains("Nested TUI commands")

let blockedSsh = run(wing & "tui --command " & quoteShell(
    "machine connect lab"))
doAssert blockedSsh.code != 0
doAssert blockedSsh.output.contains("Interactive ssh is disabled")
