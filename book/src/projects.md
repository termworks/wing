# Projects

Projects are named paths with optional namespace, language, framework, tags,
and timestamps.

```sh
wing project add api --path ~/code/api --language Go --tags service
wing project list --json
wing project info api
wing project set api --framework cobra
wing project discover ~/code --depth 2
wing project import ~/code --dry-run
```

## Where a project lives

A project is registered with the machine it is on. Nothing changes for projects on this machine —
they simply have no machine recorded — but once a project is somewhere else, every question about it
has two halves, and the registry answers both.

```sh
wing project add api --path /srv/api --machine lab
wing project set api --machine local        # move it back to this machine
wing project list                           # the Machine column
wing project list --machine lab             # only what is on lab
wing project list --local
wing machine list                           # every machine, and how many projects are on it
```

```
 Name   Username  Addresses           Tags  Projects  OS
 lab    tester    10.0.0.1:22:local   gpu   8         Ubuntu 26.04
 build  tester    10.0.0.2:22:local   None  0         unknown
 local  -         -                   None  9         this machine
```

There is no separate "hosts" registry — a machine is the host, and the project count is a column on
it. This machine gets a `local` row even though it is not registered, because it holds projects too.
A machine with none still gets a row: "nothing here yet" and "no such machine" are different
answers, and only one of them means you have not run discovery.

### Names are qualified by machine

The same name on two machines is two projects — a `deploy` on the build server and a `deploy` here
are not the same thing, and on a laptop that talks to five servers there will be several such pairs.
So a project is addressed as `name`, or as `host:name` when the bare name is ambiguous:

```
$ wing where api
'api' is on 2 machines: lab:api, local:api — name one of those instead
```

Both halves of that answer can be typed straight back in. `local:` names this machine.

## Finding the projects on a machine

```sh
wing project discover ~/code --machine lab --depth 3        # look
wing project discover ~/code --machine lab --register       # and keep
wing project discover ~/code --all-machines --register
wing project discover ~/code --register                     # this machine
```

One `find` per machine, run over ssh, all machines at once — a round trip per candidate directory
would take minutes. It looks for the markers that mean "a project is here" (`.git`, `Cargo.toml`,
`go.mod`, `*.nimble`, `pyproject.toml`, `v.mod`, `*.cabal`, `.make.lua` and the rest) and folds the
several markers a polyglot project has into one entry.

Without `--register` it prints what it found and keeps nothing, so a scan can be looked at before it
becomes registry entries. Registration merges rather than replaces: re-running discovery is how the
registry stays true, so it has to be safe to repeat, and a machine that is switched off does not
lose its projects.

## Getting into a project

```sh
wing ssh api                 # a shell in the project, wherever it is
wing ssh lab:api             # …on that machine specifically
wing ssh lab                 # just the machine
wing ssh lab:api -- 'git status'
wing ssh api --cd src        # start somewhere else
wing where api               # print the path (local) or the ssh command (remote)
```

`wing ssh` takes a machine or a project. On a remote project it opens a login shell already inside
the directory — one lookup and one `cd`, and it is the same command whether the project turns out to
be here or three machines away. On a local project it is a shell in that directory.

A bare name is read as a machine first, since `wing ssh lab` reads as a machine; `--project` says
otherwise and `host:name` is never ambiguous.

`wing where` prints instead of entering, which is what a shell function wants:

```sh
cd "$(wing where api)"       # for a local project
```
