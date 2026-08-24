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
| **Hosts** | every machine with projects on it, how many, which languages, and what it is — the same answer `wing hosts` gives |
| **Projects** | every project with the host it lives on, its path and language |
| **Machines** | the registry: user, addresses, tags, and the OS from the last `machine facts` |
| **Templates** | what `wing template list` shows |
| **Sync** | the named sync targets |

Hosts comes first because it is the question a dashboard is opened to answer: where is everything.
A machine with no projects still gets a row, since "nothing here yet" and "no such machine" are
different answers.

The OS column on Hosts and Machines comes from whatever `wing machine facts` last collected, so it
is blank until that has run once and is never gathered while the dashboard is opening.

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
