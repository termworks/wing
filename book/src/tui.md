# TUI

The TUI provides a terminal dashboard over the same command/storage logic used
by the CLI.

```sh
wing tui
wing tui --snapshot
wing tui --command "project list"
```

Inside the TUI, `a` opens field-based add forms, `:` opens a command palette,
and overlays support scrolling for long output.

## The views

| | |
|---|---|
| **Projects** | every project with the machine it lives on, its path and language |
| **Machines** | every machine: addresses, how many projects are on it, and what it is — plus a `local` row for this one |
| **Templates** | what `wing template list` shows |
| **Sync** | the named sync targets |

There is no separate "hosts" view: a machine *is* the host, and how many projects are on it is a
column rather than a screen. This machine gets a `local` row even though it is not in the registry —
a list that answers "where is everything" with everything except here is not answering.

The OS column comes from whatever `wing machine facts` last collected, so it is blank until that has
run once, and is never gathered while the dashboard is opening.

## Keys

```
↑/↓ move · ←/→ tabs · 1-9 jump to a tab · enter details
s where · a add · d delete · / filter · : command · r reload · q quit
```

`s` on a project shows how to reach it — the path if it is here, the ssh command if it is not. It
prints rather than connects: the TUI owns the terminal, so it cannot hand it to ssh and give it
back. Copy the line, or leave the TUI and run `wing ssh NAME`.

`enter` and `d` act on the project on *that host*: with the same name on two machines, the row you
are on is the one that is opened or removed.
