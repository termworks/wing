import std/[json, os, strutils]

import test_support

compileBinary()

let envPrefix = freshEnv("exports")
let dp = dp(envPrefix)
let templateRoot = "/tmp/devpilot-exports-template"
let exportPath = "/tmp/devpilot-exports-copy"
resetDir(templateRoot)
removeDir(exportPath)

discard checked(dp & "project add demo --path /tmp/demo --language Nim")
discard checked(dp & "machine add lab 127.0.0.1:22:local --username tester")
discard checked(dp & "template add base --description desc --path " &
    quoteShell(templateRoot))

let projectsJson = parseJson(checked(dp & "project list --json"))
doAssert projectsJson[0]["name"].getStr() == "demo"
doAssert projectsJson[0]["language"].getStr() == "Nim"

let machinesJson = parseJson(checked(dp & "machine list --json"))
doAssert machinesJson[0]["hosts"][0]["ip"].getStr() == "127.0.0.1"

let templatesJson = parseJson(checked(dp & "template list --json"))
doAssert templatesJson[0]["name"].getStr() == "base"

let allJson = parseJson(checked(dp & "data export --format json"))
doAssert allJson["projects"][0]["name"].getStr() == "demo"

discard checked(dp & "data export --format toml --path " & quoteShell(exportPath))
doAssert fileExists(exportPath / "manifest.toml")

let refused = run(dp & "data import " & quoteShell(exportPath))
doAssert refused.code != 0
doAssert refused.output.contains("Refusing to overwrite")

let importEnv = freshEnv("exports-import")
let dpImport = dp(importEnv)
discard checked(dpImport & "data import " & quoteShell(exportPath))
let importedProject = checked(dpImport & "project info demo")
doAssert importedProject.contains("Project: demo")

discard checked(dpImport & "data import " & quoteShell(exportPath) & " --merge")

let completions = checked(dp & "completions bash")
doAssert completions.contains("project machine")
doAssert not completions.contains("workspace")
doAssert completions.contains("data")

let markdown = checked(dp & "help --markdown")
doAssert markdown.contains("devpilot command reference")
