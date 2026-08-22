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
