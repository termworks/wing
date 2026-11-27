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
`WING_TOKEN` override it. Requests go through `curl`.

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
