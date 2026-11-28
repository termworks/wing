# The wing server

A wing server (such as wing.bresilla.com) keeps what is not about one machine: every project and
its remotes, each project's tasks and plans, and the templates projects are made from. wing on each
machine talks to it with a token made on the server's settings page.

```sh
wing server login https://wing.bresilla.com --token wing_…
wing server status
wing server sync          # register every project this machine knows
```

The token is kept in `$XDG_DATA_HOME/wing/server.json`, readable by you only. `WING_SERVER` and
`WING_TOKEN` override it. Requests go through `curl`, and say which machine they come from, so the
settings page shows where each token was last used. A token can be read-only, and can expire.

```sh
wing search zebrafish     # projects, tasks, plans, and every file of docs, rules, agents, skills, templates
```

## Projects

Once logged in, a project is registered on the server whenever wing adds or changes one here:
`wing new`, `project add`, `clone`, `adopt`, `import`, `discover --register`, `set` and `tag`.
The server reads the checkout's git remotes; a remote on the server's git host brings the
project's version, commits, issues and builds onto its page.

Each registration also says which machine has the project checked out and where, so the
project's page lists every checkout. Removing a project here never removes it on the server:
its tasks live there.

```sh
wing new rust ~/code/thing --namespace termworks     # template, git, registry, server
wing new rust ~/code/thing --repo --owner termworks  # and its repository on git, as origin
```

`--repo` needs a token from the git host, with write access, on the server's settings page.

## Docs

Each project has docs on the server: a README, notes, designs, pictures, edited in the browser
(markdown with a live preview) or from here.

```sh
wing doc                           # the current project's files
wing doc edit notes/design.md      # in $EDITOR; a new path makes a new file
wing doc add ./diagram.png
wing doc show notes/design.md
wing doc rm notes                  # a folder, and what is in it
```

## Tasks and plans

Every task and every plan belongs to one project, numbered within it. The project is the one the
current directory is in (or `--project NAME`, or `WING_PROJECT`).

```sh
wing todo                          # open tasks, what is being done first
wing todo add fix the release +1 !high
wing todo start 3
wing todo done 3
wing todo edit 4 --due 2026-12-01 --notes "after the freeze"
wing todo --all                    # every project's
wing plan add first release --notes "what it takes"
wing plan show 1
wing plan close 1
```

In a task's text, `+PLAN` puts it in a plan (its number, or a one-word title), and `!high` or
`!low` sets its priority.

A task can follow an issue on the git host: `wing todo edit 4 --issue 12`. Marking it done closes
the issue; reopening it opens the issue again. `wing todo import` makes a task of every open issue
that no task follows yet.

## Templates

Templates are edited on the server, in its Templates tab: every file of every template, with new
files, uploads, renames and the executable bit. `common/` is there too.

```sh
wing template pull                 # mirror them here (also done every 10 minutes on use)
wing template push rust ./rust     # upload a template folder
wing template push --all           # every folder under config/templates
```

Pulled templates live in `$XDG_DATA_HOME/wing/server/templates` and win over every other
template root, since the server is where they are edited.

Generated projects carry no wing file of their own.

## Skills

Agent skills (a folder with a `SKILL.md`, and whatever it points at) are kept on the server the
same way, in its Skills tab, and edited there.

```sh
wing skill pull                    # mirror them, and link each into every agent
wing skill list                    # what is here, and where it is linked
wing skill push --all ~/old/skills # upload every folder that has a SKILL.md
wing skill push NAME DIR
```

Pulled skills live in `$XDG_DATA_HOME/wing/server/skills` and are linked into
`~/.claude/skills`, `~/.codex/skills` and `~/.agents/skills` (`WING_SKILL_TARGETS`,
colon-separated, replaces that list). A link another tool made is taken over; a real folder of
the same name is left alone and reported. When a skill is deleted on the server, the next pull
removes it and its links.

## Agents

An agent is a profile for a coding agent: a folder with an `AGENT.md`, one schema for all of
them, edited in the server's Agents tab.

```yaml
---
name: reviewer
description: Reviews a change for bugs and risky edits; never changes anything.
model: opus                  # optional; empty means the tool's default
skills: [doccleanup]
tools:
  allow: [read, grep, glob, bash(git diff *), web.search]
  ask:   [write]
  deny:  [edit, bash(rm *), bash(git push*)]
default: deny                # anything not listed
---
You review changes. ...
```

Rules are `read`, `grep`, `glob`, `edit`, `write`, `bash`, `bash(PATTERN)`, `web.search`,
`web.fetch` and `task`. Deny wins over ask, ask over allow.

```sh
wing agent pull [--notes]          # write every agent for each coding tool installed here
wing agent list
wing agent new NAME ROLE...
wing agent edit NAME
```

`pull` writes each agent in the format of every coding tool that is installed on the machine.
Where a tool cannot express a rule, the agent gets the stricter reading, never the looser one,
and `--notes` says what was left out. A file wing did not write is never touched; files of an
agent deleted on the server are removed.

## Rules

Rules are the standing instructions agents read: one set for everywhere, and one per project,
edited in the server's Rules tab (and each project's).

```sh
wing rules                         # the global rules
wing rules edit                    # in $EDITOR; `wing rules edit PROJECT` for a project's
wing rules push global ~/.claude/CLAUDE.md   # make a file of yours the rules
wing rules pull                    # write them here (the hourly sync does it too)
```

The global rules go to each coding tool installed here, in the file that tool reads. A project's
rules go into its checkout as `AGENTS.md`, and only when the project has rules written, or agents
chosen in its settings; those agents are named in it, each with its role. Nothing else is ever
written into a checkout. A file wing did not write, with other words in it, is left alone: push
it first to make it the rules.
