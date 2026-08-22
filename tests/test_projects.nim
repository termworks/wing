import std/strutils

import test_support

compileBinary()

let envPrefix = freshEnv("projects")
let wing = wing(envPrefix)

discard checked(wing & "project add demo --path /tmp/demo --language go --framework cobra --tags cli")

let raw = checked(wing & "project list --raw")
doAssert "demo\tdefault\t/tmp/demo\tgo" in raw

let info = checked(wing & "project info demo")
doAssert info.contains("Project: demo")
doAssert info.contains("Framework: cobra")
doAssert info.contains("Tags: cli")

discard checked(wing & "project set demo --path /tmp/demo2 --language nim " &
    "--framework bobabrew --description updated")
let updated = checked(wing & "project info demo")
doAssert updated.contains("Path: /tmp/demo2")
doAssert updated.contains("Language: nim")
doAssert updated.contains("Framework: bobabrew")
doAssert updated.contains("Description: updated")

discard checked(wing & "project tag add demo tui")
discard checked(wing & "project tag add demo tui")
let tagged = checked(wing & "project info demo")
doAssert tagged.contains("Tags: cli, tui")
discard checked(wing & "project tag remove demo cli")
let untagged = checked(wing & "project info demo")
doAssert untagged.contains("Tags: tui")

discard checked(wing & "project rename demo renamed")
let renamed = checked(wing & "project info renamed")
doAssert renamed.contains("Project: renamed")

let duplicate = run(wing & "project add demo --path /tmp/other")
doAssert duplicate.code == 0
let duplicateRename = run(wing & "project rename renamed demo")
doAssert duplicateRename.code != 0
doAssert duplicateRename.output.contains("already exists")

discard checked(wing & "project --namespace other add renamed --path /tmp/other")
discard checked(wing & "project --namespace other set renamed --language zig")
let defaultInfo = checked(wing & "project info renamed")
doAssert defaultInfo.contains("Language: nim")
let otherInfo = checked(wing & "project --namespace other info renamed")
doAssert otherInfo.contains("Language: zig")

discard checked(wing & "project remove renamed")

let missing = run(wing & "project info renamed")
doAssert missing.code != 0
