import std/[json, os, strutils]

import test_support

compileBinary()

let envPrefix = freshEnv("exports")
let wing = wing(envPrefix)
let templateRoot = "/tmp/wing-exports-template"
let exportPath = "/tmp/wing-exports-copy"
resetDir(templateRoot)
removeDir(exportPath)

discard checked(wing & "project add demo --path /tmp/demo --language Nim")
discard checked(wing & "machine add lab 127.0.0.1:22:local --username tester")
discard checked(wing & "template add base --description desc --path " &
    quoteShell(templateRoot))

let projectsJson = parseJson(checked(wing & "project list --json"))
doAssert projectsJson[0]["name"].getStr() == "demo"
doAssert projectsJson[0]["language"].getStr() == "Nim"

let machinesJson = parseJson(checked(wing & "machine list --json"))
doAssert machinesJson[0]["hosts"][0]["ip"].getStr() == "127.0.0.1"

let templatesJson = parseJson(checked(wing & "template list --json"))
doAssert templatesJson[0]["name"].getStr() == "base"

let allJson = parseJson(checked(wing & "data export --format json"))
doAssert allJson["projects"][0]["name"].getStr() == "demo"

discard checked(wing & "data export --format toml --path " & quoteShell(exportPath))
doAssert fileExists(exportPath / "manifest.toml")

let refused = run(wing & "data import " & quoteShell(exportPath))
doAssert refused.code != 0
doAssert refused.output.contains("Refusing to overwrite")

let importEnv = freshEnv("exports-import")
let wingImport = wing(importEnv)
discard checked(wingImport & "data import " & quoteShell(exportPath))
let importedProject = checked(wingImport & "project info demo")
doAssert importedProject.contains("Project: demo")

discard checked(wingImport & "data import " & quoteShell(exportPath) & " --merge")

let completions = checked(wing & "completions bash")
doAssert completions.contains("project machine")
doAssert not completions.contains("workspace")
doAssert completions.contains("data")

let markdown = checked(wing & "help --markdown")
doAssert markdown.contains("wing command reference")
