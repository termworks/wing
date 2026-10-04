# Sync (`wing sync`)

`wing sync` synchronizes a registered project with a directory on a remote
machine using **rsync over SSH**. wing builds the rsync command from the
project (local path) and the machine (SSH target) you already have registered,
and reuses the machine's **ControlMaster socket** so `connect`, `check --ssh`,
and `sync` share one SSH connection.

## Model

A **sync target** ties together three things from your registry:

- a **project** (provides the local path),
- a **machine** (provides the SSH target: user, host, port, key, ProxyJump,
  agent forwarding),
- a **remote path** on that machine.

```sh
wing sync add app-lab \
  --project app \
  --machine lab \
  --remote /srv/app \
  --direction push \
  --exclude .git --exclude node_modules

wing sync run app-lab              # push
wing sync run app-lab --dry-run    # print the exact rsync command
wing sync run app-lab --direction pull   # remote -> local
```

## What wing runs

Something equivalent to:

```sh
rsync --archive --verbose --human-readable --compress \
      [--delete] [--exclude=PAT ...] \
      --rsh 'ssh -o ControlMaster=auto -o ControlPath=…/<machine>-<iface> …' \
      LOCAL/  USER@HOST:REMOTE/
```

- Source trailing slash mirrors **contents** into the destination.
- `--delete` (mirror mode) is opt-in (`--delete` at `add` or `run` time).
- `--compress` is on by default.
- `--dry-run` adds rsync `-n` and prints the full command without transferring.

## Commands

```sh
wing sync add NAME --project P --machine M --remote PATH [options]
wing sync list [--raw]
wing sync info NAME [--json]
wing sync run NAME [--dry-run] [--delete] [--direction push|pull]
wing sync set NAME [--remote PATH] [--direction push|pull] [--delete|--no-delete] [--exclude ...]
wing sync rename OLD NEW
wing sync remove NAME
```

One endpoint is always the local machine. Sync targets resolve the project and
machine from the existing registries, so adding `--proxy-jump`/`--forward-agent`
to the machine automatically applies to its sync targets too.

## Syncing a project between hosts

The commands above are a registry of named targets you set up once and run again. This is the other
half: an ad-hoc copy between two machines, named the way everything else names projects.

```sh
wing sync project api tron                  # this project, onto that machine
wing sync project lab:api local             # bring it back
wing sync project lab:api tron:api          # between two machines
wing sync project api tron --to /srv/api    # a different path on the far side
wing sync project api tron --delete --exclude target --exclude .direnv
wing sync project api tron --dry-run        # print the plan, touch nothing
wing sync project api tron --register       # …and record it as a project on tron
```

`SOURCE` is a registered project (`name`, or `host:name` when the bare name is ambiguous).
`DEST` is a machine, or a project on one. A machine on its own means *the same project, over there*,
which saves registering it before the first copy.

**Where it lands**, in order: `--to` if given; else the path the destination's own registry entry
has; else the source's path, which keeps a project in the same place on every machine.

**When neither end is this machine**, the bytes are relayed through here — down, then up. That is
twice the transfer and still the right default: rsync cannot talk between two remote hosts on its
own, and the alternative needs the source to be able to ssh to the destination, which usually is not
set up and fails confusingly when it is not.

```sh
wing sync project lab:api tron --direct     # run rsync on lab instead
```

`--direct` is for when it is set up: rsync runs on the source machine and connects onward itself.

`--register` records the copy, so `wing machine list` and `wing project list` show the project on
both machines afterwards — which is the point of the machine being part of a project's identity.
