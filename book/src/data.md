# Data and backup

Data is stored under `$XDG_DATA_HOME/devpilot` or
`~/.local/share/devpilot`.

Files:

- `projects.toml`
- `machines.toml`
- `templates.toml`

Backup and restore:

```sh
dp data backup create --path ./devpilot-backup
dp data backup restore ./devpilot-backup --force
dp data export --format json
dp data import ./devpilot-backup --merge
```
