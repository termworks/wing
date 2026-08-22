# Machines

Machines store SSH targets and host interfaces, and drive a tight SSH
integration: `connect`, `check --ssh`, and `sync` all reuse one **ControlMaster
socket** per machine+interface, so the first connection stays open for ~60s and
every later operation piggybacks on it (no repeated handshakes).

```sh
dp machine add lab 127.0.0.1:22:local --username "$USER"
dp machine add bastion 10.0.0.5:22:local --username ops \
  --proxy-jump gate.example.com --forward-agent
dp machine ssh-config lab
dp machine connect lab --dry-run
dp machine check lab --ssh --timeout 2000
```

## Per-machine SSH options

- `-J, --proxy-jump PROXY` — SSH `ProxyJump` host (bastion/jump host).
- `-A, --forward-agent` — enable SSH agent forwarding.
- `-k, --key KEY` — identity file.

These are stored on the machine and applied by `connect`, `check --ssh`, the
generated `ssh-config`, and by `sync` (via rsync's `--rsh`).

## Commands

```sh
dp machine add NAME IP[:PORT][:IFACE]... [-u USER] [-k KEY] [-J PROXY] [-A]
dp machine set NAME [-u USER] [-k KEY] [-J PROXY] [-A|--no-forward-agent]
dp machine list [--raw] [--json]
dp machine info NAME
dp machine ssh-config [NAME]          # IdentitiesOnly, StrictHostKeyChecking
                                       # accept-new, ControlMaster, ProxyJump…
dp machine check NAME [--ssh] [--timeout MS]   # TCP by default; --ssh = auth test
dp machine check --all [--ssh]
dp machine connect NAME [--interface IFACE] [--command CMD] [--dry-run]
dp machine host add/remove NAME IP[:PORT][:IFACE]
dp machine rename OLD NEW
dp machine pick
dp machine remove NAME
```

The interface name (the third `IP:PORT:IFACE` field) must be `local` or a real
network interface on this machine — it labels the route, not the remote side.

## `check` vs `check --ssh`

- default (TCP): tests that the host:port is reachable.
- `--ssh`: runs `ssh … -o BatchMode=yes … true` and reports whether SSH
  **authentication** actually succeeds — the right test when "the port is open
  but my key is rejected" is the failure you care about.
