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
