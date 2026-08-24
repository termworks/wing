import std/[os, strutils]

import test_support

compileBinary()

# A project registry that cannot say which machine a project is on is a list of paths that are only
# true on one computer. These cover the addressing -- `name`, `local:name`, `machine:name` -- and
# what each command does when a name means more than one thing.
let envPrefix = freshEnv("projhosts")
let wing = wing(envPrefix)
discard checked(wing & "init")

discard checked(wing & "machine add lab 10.0.0.1:22:local --username tester")
discard checked(wing & "project add api --path /srv/api --machine lab --language go")
discard checked(wing & "project add api --path /home/me/api --language nim")
discard checked(wing & "project add solo --path /home/me/solo")

# --- a listing says where each project is -------------------------------------
let listed = checked(wing & "project list")
doAssert listed.contains("Host"), listed
doAssert listed.contains("lab"), listed
doAssert listed.contains("local"), listed

let onLab = checked(wing & "project list --machine lab")
doAssert onLab.contains("/srv/api"), onLab
doAssert not onLab.contains("/home/me/api"), onLab

let localOnly = checked(wing & "project list --local")
doAssert localOnly.contains("/home/me/api"), localOnly
doAssert not localOnly.contains("/srv/api"), localOnly

# --- hosts answers "where is everything" --------------------------------------
let hosts = checked(wing & "hosts")
doAssert hosts.contains("lab"), hosts
doAssert hosts.contains("local"), hosts

# --- a bare name that means two projects is refused, and both are typable -----
let ambiguous = run(wing & "where api")
doAssert ambiguous.code != 0
doAssert ambiguous.output.contains("lab:api"), ambiguous.output
doAssert ambiguous.output.contains("local:api"), ambiguous.output

# Both halves of that answer resolve.
doAssert checked(wing & "where local:api").strip() == "/home/me/api"
let remoteWhere = checked(wing & "where lab:api")
doAssert remoteWhere.contains("ssh"), remoteWhere
doAssert remoteWhere.contains("cd /srv/api"), remoteWhere
# An unqualified name that means exactly one project needs no qualifying.
doAssert checked(wing & "where solo").strip() == "/home/me/solo"

# --- ssh: a machine wins a bare name, a project is reached by its host --------
let toMachine = checked(wing & "ssh lab --dry-run")
doAssert toMachine.contains("tester@10.0.0.1"), toMachine
doAssert not toMachine.contains("cd "), "a machine has no directory to land in"

let toProject = checked(wing & "ssh lab:api --dry-run")
doAssert toProject.contains("cd /srv/api"), toProject
doAssert toProject.contains("exec"), toProject

# A local project is entered here rather than over ssh.
let toLocal = checked(wing & "ssh local:api --dry-run")
doAssert not toLocal.contains("ssh"), toLocal
doAssert toLocal.contains("/home/me/api"), toLocal

let nothing = run(wing & "ssh nosuchthing")
doAssert nothing.code != 0
doAssert nothing.output.contains("No machine or project"), nothing.output

# --- a project can be moved between hosts, and back --------------------------
discard checked(wing & "project set solo --machine lab")
doAssert checked(wing & "project list --machine lab").contains("solo")
discard checked(wing & "project set solo --machine local")
doAssert checked(wing & "project list --local").contains("solo")

# --- discovery needs a machine that exists ------------------------------------
let badMachine = run(wing & "project discover /tmp --machine nowhere")
doAssert badMachine.code != 0
doAssert badMachine.output.contains("not found"), badMachine.output
