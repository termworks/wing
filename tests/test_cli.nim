import std/[os, strutils]

import test_support

compileBinary()

proc packageVersion(): string =
  for line in readFile("devpilot.nimble").splitLines:
    let value = line.strip()
    if value.startsWith("version"):
      let parts = value.split('"')
      if parts.len >= 3:
        return parts[1]
  raise newException(ValueError, "could not read package version")

let envPrefix = freshEnv("cli")
let dp = dp(envPrefix)

doAssert checked(dp & "--version").strip() == packageVersion()
let help = checked(dp & "--help")
doAssert help.contains("Main commands:")
doAssert help.contains("Other commands:")
doAssert help.contains("data")
let tuiSnapshot = checked(dp & "tui --snapshot")
doAssert tuiSnapshot.contains("devpilot tui")
doAssert tuiSnapshot.contains("Projects:")
discard checked(dp & "tui --command " & quoteShell("project add tui_demo --path /tmp/tui_demo --language go"))
doAssert checked(dp & "project info tui_demo").contains("Project: tui_demo")
discard checked(dp & "project remove tui_demo")

discard checked(dp & "project add demo --path /tmp/demo --language go --tags cli")
let projects = checked(dp & "project list --raw")
doAssert "demo\tdefault\t/tmp/demo\tgo" in projects
doAssert checked(dp & "project info demo").contains("Project: demo")

discard checked(dp & "machine add lab 127.0.0.1:22:local --username tester --key /tmp/key")
let machines = checked(dp & "machine list --raw")
doAssert "lab\ttester\t127.0.0.1\t22\tlocal" in machines
doAssert checked(dp & "machine info lab").contains("Machine: lab")

let templateRoot = "/tmp/devpilot-nim-template"
let targetRoot = "/tmp/devpilot-nim-target"
removeDir(templateRoot)
removeDir(targetRoot)
createDir(templateRoot)
writeFile(templateRoot / "README.md", "hello {{PROJECT_NAME}}")
discard checked(dp & "template add base --description sample --path " &
    quoteShell(templateRoot) & " --language go")
discard checked(dp & "template apply base " & quoteShell(targetRoot) & " --name sample_app")
doAssert readFile(targetRoot / "README.md") == "hello sample_app"

let populatedSnapshot = checked(dp & "tui --snapshot")
doAssert populatedSnapshot.contains("Projects: 1")
doAssert populatedSnapshot.contains("Templates: 1")

discard checked(dp & "project remove demo")
discard checked(dp & "template remove base")
discard checked(dp & "machine remove lab")

let missing = run(dp & "project info missing")
doAssert missing.code != 0
