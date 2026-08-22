import std/[os, strutils]

import test_support

compileBinary()

proc packageVersion(): string =
  for line in readFile("wing.nimble").splitLines:
    let value = line.strip()
    if value.startsWith("version"):
      let parts = value.split('"')
      if parts.len >= 3:
        return parts[1]
  raise newException(ValueError, "could not read package version")

let envPrefix = freshEnv("cli")
let wing = wing(envPrefix)

doAssert checked(wing & "--version").strip() == packageVersion()
let help = checked(wing & "--help")
doAssert help.contains("Main commands:")
doAssert help.contains("Other commands:")
doAssert help.contains("data")
let tuiSnapshot = checked(wing & "tui --snapshot")
doAssert tuiSnapshot.contains("wing tui")
doAssert tuiSnapshot.contains("Projects:")
discard checked(wing & "tui --command " & quoteShell("project add tui_demo --path /tmp/tui_demo --language go"))
doAssert checked(wing & "project info tui_demo").contains("Project: tui_demo")
discard checked(wing & "project remove tui_demo")

discard checked(wing & "project add demo --path /tmp/demo --language go --tags cli")
let projects = checked(wing & "project list --raw")
doAssert "demo\tdefault\t/tmp/demo\tgo" in projects
doAssert checked(wing & "project info demo").contains("Project: demo")

discard checked(wing & "machine add lab 127.0.0.1:22:local --username tester --key /tmp/key")
let machines = checked(wing & "machine list --raw")
doAssert "lab\ttester\t127.0.0.1\t22\tlocal" in machines
doAssert checked(wing & "machine info lab").contains("Machine: lab")

let templateRoot = "/tmp/wing-nim-template"
let targetRoot = "/tmp/wing-nim-target"
removeDir(templateRoot)
removeDir(targetRoot)
createDir(templateRoot)
writeFile(templateRoot / "README.md", "hello {{PROJECT_NAME}}")
discard checked(wing & "template add base --description sample --path " &
    quoteShell(templateRoot) & " --language go")
discard checked(wing & "template apply base " & quoteShell(targetRoot) & " --name sample_app")
doAssert readFile(targetRoot / "README.md") == "hello sample_app"

let populatedSnapshot = checked(wing & "tui --snapshot")
doAssert populatedSnapshot.contains("Projects: 1")
doAssert populatedSnapshot.contains("Templates: 1")

discard checked(wing & "project remove demo")
discard checked(wing & "template remove base")
discard checked(wing & "machine remove lab")

let missing = run(wing & "project info missing")
doAssert missing.code != 0
