# Machines

Machines store SSH targets and host interfaces, and drive a tight SSH
integration: `connect`, `check --ssh`, and `sync` all reuse one **ControlMaster
socket** per machine+interface, so the first connection stays open for ~60s and
every later operation piggybacks on it (no repeated handshakes).

```sh
wing machine add lab 127.0.0.1:22:local --username "$USER"
wing machine add bastion 10.0.0.5:22:local --username ops \
  --proxy-jump gate.example.com --forward-agent
wing machine ssh-config lab
wing machine connect lab --dry-run
wing machine check lab --ssh --timeout 2000
```

## Per-machine SSH options

- `-J, --proxy-jump PROXY` — SSH `ProxyJump` host (bastion/jump host).
- `-A, --forward-agent` — enable SSH agent forwarding.
- `-k, --key KEY` — identity file.

These are stored on the machine and applied by `connect`, `check --ssh`, the
generated `ssh-config`, and by `sync` (via rsync's `--rsh`).

## Commands

```sh
wing machine add NAME IP[:PORT][:IFACE]... [-u USER] [-k KEY] [-J PROXY] [-A]
wing machine set NAME [-u USER] [-k KEY] [-J PROXY] [-A|--no-forward-agent]
wing machine list [--raw] [--json]
wing machine info NAME
wing machine ssh-config [NAME]          # IdentitiesOnly, StrictHostKeyChecking
                                       # accept-new, ControlMaster, ProxyJump…
wing machine check NAME [--ssh] [--timeout MS]   # TCP by default; --ssh = auth test
wing machine check --all [--ssh]
wing machine connect NAME [--interface IFACE] [--command CMD] [--dry-run]
wing machine host add/remove NAME IP[:PORT][:IFACE]
wing machine rename OLD NEW
wing machine pick
wing machine remove NAME
```

The interface name (the third `IP:PORT:IFACE` field) must be `local` or a real
network interface on this machine — it labels the route, not the remote side.

## `check` vs `check --ssh`

- default (TCP): tests that the host:port is reachable.
- `--ssh`: runs `ssh … -o BatchMode=yes … true` and reports whether SSH
  **authentication** actually succeeds — the right test when "the port is open
  but my key is rejected" is the failure you care about.

## Tags, and addressing a group

A machine can carry tags, and a tag is how a command names a group without listing it — a list goes
stale the moment the fleet changes.

```sh
wing machine add gpu-1 10.0.0.5 --tag gpu --tag lab
wing machine tag gpu-1 cuda
wing machine untag gpu-1 lab
wing machine list                       # the Tags column
```

Every command below takes `NAME`, `--tag TAG` (repeatable), or `--all`.

## Running a command on machines

```sh
wing machine run lab -- uptime
wing machine run --tag gpu -- nvidia-smi --query-gpu=name --format=csv
wing machine run --all --timeout 5000 -- 'systemctl is-active docker'
wing machine run --tag gpu --quiet -- hostname | sort
```

Everything after `--` is handed to the remote shell as one string, so quoting is the remote's
business rather than something that has to survive being split and rejoined here.

Machines are contacted **concurrently** and the output is grouped under the machine that produced
it, in name order — output that reorders itself between two runs cannot be compared, and comparing
two runs is most of why you ran it. `--quiet` drops the headers for piping. The exit status is
non-zero if any machine failed, and `--timeout` bounds the whole thing so one dead host cannot hang
the rest.

`BatchMode` is forced on: nothing here is attached to a terminal, so a machine that wants a
passphrase fails and says so instead of quietly waiting on a prompt nobody can see.

## What a machine is

```sh
wing machine facts --all              # collect once, then read from cache
wing machine facts --all --refresh    # ask again
wing machine facts lab --json
```

One shell script per machine — os, kernel, arch, cpus, memory, disk, uptime — collected in a single
round trip and kept in the data directory. It is not configuration: nobody edits it, and losing it
costs one round trip.

```
 Machine  OS                Arch    CPUs  Memory       Disk               Uptime
 lab      Ubuntu 26.04 LTS  x86_64  24    14Gi / 58Gi  222G / 915G (26%)  up 12 hours
```

## Moving files

```sh
wing machine push ./dist/app lab:/srv/app/          # one or many sources
wing machine push ./config --tag web /etc/myapp/    # the same file to a group
wing machine pull lab:/var/log/app.log ./logs/
wing machine push --dry-run ./big lab:/srv/
```

rsync over the same SSH options everything else uses, so a transfer shares the ControlMaster socket
rather than opening a second connection. The remote side is the argument with the colon, which is
what scp and rsync already taught your fingers.

`pull` takes exactly one machine: two would write to the same local path, and the second would
silently win.
