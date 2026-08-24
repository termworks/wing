import std/[os, strutils]

import test_support

compileBinary()

# Moving a project between machines. These cover the resolution -- which project, which machine,
# which path on the far side -- and the guards. Whether rsync copies bytes is rsync's business.
let envPrefix = freshEnv("synchosts")
let wing = wing(envPrefix)
discard checked(wing & "init")

discard checked(wing & "machine add lab 10.0.0.1:22:local --username tester")
discard checked(wing & "machine add box 10.0.0.2:22:local --username tester")
discard checked(wing & "project add api --path /home/me/api --language go")

# --- a destination that is only a machine means "the same project, over there" ---
let toMachine = checked(wing & "sync project api box --dry-run")
doAssert toMachine.contains("local:api"), toMachine
doAssert toMachine.contains("box:api"), toMachine

# --- the path on the far side ------------------------------------------------
# Nothing is registered on box yet, so the source's own path is the guess.
doAssert toMachine.contains("/home/me/api"), toMachine
# Once something is registered there, that is where it goes.
discard checked(wing & "project add api --path /srv/api --machine box")
let toRegistered = checked(wing & "sync project local:api box --dry-run")
doAssert toRegistered.contains("/srv/api"), toRegistered
# And --to wins over both.
let toOverride = checked(wing & "sync project local:api box --to /opt/api --dry-run")
doAssert toOverride.contains("/opt/api"), toOverride

# --- an ambiguous source is refused, with both names spelled out -------------
let ambiguous = run(wing & "sync project api box --dry-run")
doAssert ambiguous.code != 0
doAssert ambiguous.output.contains("lab:api") or
    ambiguous.output.contains("local:api"), ambiguous.output

# --- neither end here: relayed by default, direct when asked -----------------
discard checked(wing & "project add web --path /srv/web --machine lab")
let relayed = checked(wing & "sync project lab:web box --dry-run")
doAssert relayed.contains("via this machine"), relayed
doAssert relayed.contains("here"), relayed

let straight = run(wing & "sync project lab:web box --direct --dry-run")
doAssert straight.output.contains("direct"), straight.output
doAssert straight.output.contains("run on lab"), straight.output

# --- copying a place onto itself is a mistake, not a no-op -------------------
let sameSpot = run(wing & "sync project lab:web lab --dry-run")
doAssert sameSpot.code != 0
doAssert sameSpot.output.contains("same place"), sameSpot.output

# --- names that do not resolve ----------------------------------------------
let noProject = run(wing & "sync project nosuch box")
doAssert noProject.code != 0
doAssert noProject.output.contains("No project"), noProject.output

let noMachine = run(wing & "sync project local:api nowhere")
doAssert noMachine.code != 0
doAssert noMachine.output.contains("not found"), noMachine.output

# --- the named-target registry still works -----------------------------------
# `sync project` took a word that used to be an option name, so the old commands are worth a look.
discard checked(wing & "sync add nightly --project api --machine lab --remote /srv/api")
doAssert checked(wing & "sync list").contains("nightly")
