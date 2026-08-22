import std/[os, strutils]

import test_support

compileBinary()

let envPrefix = freshEnv("discovery")
let wing = wing(envPrefix)
let root = "/tmp/wing-discovery-root"
resetDir(root)

createDir(root / "goapp")
writeFile(root / "goapp" / "go.mod", "module example.com/goapp\n")

createDir(root / "nested")
createDir(root / "nested" / "nimapp")
writeFile(root / "nested" / "nimapp" / "nimapp.nimble", "version = \"0.1.0\"\n")

createDir(root / "target")
createDir(root / "target" / "ignored")
writeFile(root / "target" / "ignored" / "Cargo.toml", "[package]\n")

let shallow = checked(wing & "project discover " & quoteShell(root) & " --depth 1")
doAssert shallow.contains("goapp")
doAssert not shallow.contains("nimapp")
doAssert not shallow.contains("ignored")

let deep = checked(wing & "project discover " & quoteShell(root) & " --depth 2")
doAssert deep.contains("goapp")
doAssert deep.contains("nimapp")
doAssert not deep.contains("ignored")

let json = checked(wing & "project discover " & quoteShell(root) &
    " --json --depth 2")
doAssert json.contains("\"name\": \"goapp\"")
doAssert json.contains("\"language\": \"Nim\"")

let dryRun = checked(wing & "project import " & quoteShell(root) &
    " --dry-run --depth 2")
doAssert dryRun.contains("Would import: goapp")
let emptyList = checked(wing & "project list --raw")
doAssert not emptyList.contains("goapp")

let imported = checked(wing & "project import " & quoteShell(root) & " --depth 2")
doAssert imported.contains("Imported: goapp")
doAssert imported.contains("Imported: nimapp")
let projectList = checked(wing & "project list --raw")
doAssert projectList.contains("goapp")
doAssert projectList.contains("nimapp")

let duplicateImport = checked(wing & "project import " & quoteShell(root) &
    " --depth 2")
doAssert duplicateImport.contains("Skipped duplicate: goapp")

discard checked(wing & "project --namespace alt import " & quoteShell(root) &
    " --depth 1")
let altList = checked(wing & "project --namespace alt list --raw")
doAssert altList.contains("goapp\talt")
