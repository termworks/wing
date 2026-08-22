import std/strutils

import test_support

compileBinary()

let envPrefix = freshEnv("machines")
let wing = wing(envPrefix)

discard checked(wing & "machine add lab 127.0.0.1:22:local --username tester --key /tmp/key")

let raw = checked(wing & "machine list --raw")
doAssert "lab\ttester\t127.0.0.1\t22\tlocal" in raw

let info = checked(wing & "machine info lab")
doAssert info.contains("Machine: lab")
doAssert info.contains("127.0.0.1:22")

discard checked(wing & "machine set lab --username operator --key /tmp/new-key")
let updated = checked(wing & "machine info lab")
doAssert updated.contains("Username: operator")
doAssert updated.contains("Key: /tmp/new-key")

discard checked(wing & "machine host add lab 127.0.0.2:2200:lo")
let withHost = checked(wing & "machine info lab")
doAssert withHost.contains("127.0.0.2:2200")

let connectDryRun = checked(wing & "machine connect lab --dry-run")
doAssert connectDryRun.contains("ssh")
doAssert connectDryRun.contains("-i /tmp/new-key")
doAssert connectDryRun.contains("operator@127.0.0.1")

let sshConfig = checked(wing & "machine ssh-config lab")
doAssert sshConfig.contains("Host lab-local")
doAssert sshConfig.contains("HostName 127.0.0.1")
doAssert sshConfig.contains("User operator")
doAssert sshConfig.contains("IdentityFile /tmp/new-key")
doAssert sshConfig.contains("Host lab-lo")

let duplicateHost = run(wing & "machine host add lab 127.0.0.3:22:lo")
doAssert duplicateHost.code != 0
doAssert duplicateHost.output.contains("already exists")

discard checked(wing & "machine host remove lab lo")
let withoutHost = checked(wing & "machine info lab")
doAssert not withoutHost.contains("127.0.0.2:2200")

discard checked(wing & "machine rename lab lab2")
let renamed = checked(wing & "machine info lab2")
doAssert renamed.contains("Machine: lab2")

discard checked(wing & "machine add other 127.0.0.5:22:local")
let duplicateRename = run(wing & "machine rename lab2 other")
doAssert duplicateRename.code != 0
doAssert duplicateRename.output.contains("already exists")

let duplicateIface = run(wing & "machine add lab2 127.0.0.2:22:local")
doAssert duplicateIface.code != 0
doAssert duplicateIface.output.contains("already exists")

let badIp = run(wing & "machine add broken nope:22:local")
doAssert badIp.code != 0
doAssert badIp.output.contains("Invalid ip")

discard checked(wing & "machine add closed 192.0.2.1:1:local --username tester")
let health = run(wing & "machine check closed --timeout 20")
doAssert health.code != 0
doAssert health.output.contains("unreachable")

discard checked(wing & "machine remove lab2")

let missing = run(wing & "machine info lab2")
doAssert missing.code != 0
