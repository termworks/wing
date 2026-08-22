import std/[os, strutils]

import test_support

compileBinary()

let envPrefix = freshEnv("backup")
let dp = dp(envPrefix)
let dataRoot = "/tmp/devpilot-backup-data" / "devpilot"
let backupPath = "/tmp/devpilot-backup-copy"
removeDir(backupPath)

discard checked(dp & "project add persisted --path /tmp/persisted")
doAssert readFile(dataRoot / "projects.toml").contains("schema_version = 1")

let created = checked(dp & "data backup create --path " & quoteShell(backupPath))
doAssert created.contains("Backup created:")
doAssert fileExists(backupPath / "manifest.toml")
doAssert fileExists(backupPath / "projects.toml")
doAssert fileExists(backupPath / "machines.toml")
doAssert fileExists(backupPath / "templates.toml")

removeDir(dataRoot)
discard checked(dp & "data backup restore " & quoteShell(backupPath))
let restoredInfo = checked(dp & "project info persisted")
doAssert restoredInfo.contains("Project: persisted")

let refused = run(dp & "data backup restore " & quoteShell(backupPath))
doAssert refused.code != 0
doAssert refused.output.contains("Refusing to overwrite")

discard checked(dp & "data backup restore " & quoteShell(backupPath) & " --force")

writeFile(dataRoot / "projects.toml",
    "[[projects]]\nname = \"legacy\"\npath = \"/tmp/legacy\"\n")
let legacyInfo = checked(dp & "project info legacy")
doAssert legacyInfo.contains("Project: legacy")
discard checked(dp & "project add migrated --path /tmp/migrated")
doAssert readFile(dataRoot / "projects.toml").contains("schema_version = 1")

writeFile(dataRoot / "projects.toml", "schema_version = 999\n\nprojects = []\n")
let future = run(dp & "project list")
doAssert future.code != 0
doAssert future.output.contains("Unsupported schema version 999")
