# Data and backup

Data is stored under `$XDG_DATA_HOME/wing` or
`~/.local/share/wing`.

Files:

- `projects.toml`
- `machines.toml`
- `templates.toml`

Backup and restore:

```sh
wing data backup create --path ./wing-backup
wing data backup restore ./wing-backup --force
wing data export --format json
wing data import ./wing-backup --merge
```
