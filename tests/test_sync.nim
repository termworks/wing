import std/[os, strutils, tables]

import ../src/devpilot_sync
import test_support

compileBinary()

let envPrefix = freshEnv("sync")
let dp = dp(envPrefix)

# --- prerequisites: a registered project and machine -----------------------
let projPath = "/tmp/devpilot-sync-proj"
resetDir(projPath)
discard checked(dp & "project add app --path " & quoteShell(projPath) &
    " --language go")
discard checked(dp & "machine add lab 127.0.0.1:22:local --username tester")

# --- CRUD -------------------------------------------------------------------
discard checked(dp &
    "sync add app-lab --project app --machine lab --remote /srv/app --direction push --exclude .git")
let raw = checked(dp & "sync list --raw")
doAssert "app-lab\tapp\tlab\t/srv/app\tpush" in raw, raw

let info = checked(dp & "sync info app-lab")
doAssert info.contains("Sync: app-lab")
doAssert info.contains("Direction: push")
doAssert info.contains("Exclude: .git")

let infoJson = checked(dp & "sync info app-lab --json")
doAssert infoJson.contains("\"remote_path\": \"/srv/app\"")

# set + rename
discard checked(dp & "sync set app-lab --direction pull --no-delete")
doAssert checked(dp & "sync info app-lab").contains("Direction: pull")
discard checked(dp & "sync rename app-lab app-prod")
doAssert checked(dp & "sync info app-prod").contains("Sync: app-prod")

# validation: add without --remote fails
let badAdd = run(dp & "sync add bogus --project app --machine lab")
doAssert badAdd.code != 0
doAssert badAdd.output.contains("--remote")
# validation: unknown project fails
let badProj = run(dp & "sync add bogus2 --project nope --machine lab --remote /x")
doAssert badProj.code != 0
doAssert badProj.output.contains("not registered")

discard checked(dp & "sync remove app-prod")
doAssert run(dp & "sync info app-prod").code != 0

# --- rsync command builder --------------------------------------------------
# push: src = local (contents), dst = remote; archive + compress + rsh.
let push = buildRsyncCmd("/code/app/", "tester@1.2.3.4:/srv/app/",
    "ssh -i /home/u/.ssh/k", doDelete = false, excludes = @[".git",
    "node_modules"], dryRun = false, compress = true)
doAssert push[0] == "rsync", "argv[0] should be rsync"
doAssert "--archive" in push, "rsync needs --archive"
doAssert "--compress" in push, "compress flag missing"
doAssert "--delete" notin push, "delete should be off"
doAssert "--exclude=.git" in push, "exclude .git missing"
doAssert "--exclude=node_modules" in push
doAssert "--rsh" in push, "rsh/transport missing"
let rshIdx = push.find("--rsh")
doAssert rshIdx >= 0 and push[rshIdx + 1] == "ssh -i /home/u/.ssh/k",
    "rsh value should be the ssh command"
doAssert push[^2] == "/code/app/", "push source should be local: " & push[^2]
doAssert push[^1] == "tester@1.2.3.4:/srv/app/", "push dest should be remote"

# delete + dry-run flags surface correctly
let del = buildRsyncCmd("/a/", "h:/b/", "ssh", doDelete = true,
    excludes = @[], dryRun = true, compress = false)
doAssert "--delete" in del
doAssert "--dry-run" in del
doAssert "--compress" notin del

# pull reverses src/dst (caller's responsibility; builder just places them)
let pull = buildRsyncCmd("tester@1.2.3.4:/srv/app/", "/code/app/",
    "ssh", false, @[], false, true)
doAssert pull[^2] == "tester@1.2.3.4:/srv/app/", "pull source should be remote"
doAssert pull[^1] == "/code/app/", "pull dest should be local"

# formatCmd renders a shell line for dry-run display
let rendered = formatCmd(push)
doAssert rendered.startsWith("rsync "), "formatCmd should start with rsync: " &
    rendered
doAssert "/code/app/" in rendered

# --- run --dry-run builds the rsync command and prints it -------------------
discard checked(dp & "sync add dr --project app --machine lab --remote /srv/app")
let dryRunOut = checked(dp & "sync run dr --dry-run")
doAssert dryRunOut.contains("rsync"), "dry-run should show the rsync command"
doAssert dryRunOut.contains("--archive"), "dry-run cmd needs --archive"
doAssert dryRunOut.contains("tester@"), "dry-run cmd needs the ssh target"
discard checked(dp & "sync remove dr")
