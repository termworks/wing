# Projects

Projects are named paths with optional namespace, language, framework, tags,
and timestamps.

```sh
wing project add api --path ~/code/api --language Go --tags service
wing project list --json
wing project info api
wing project set api --framework cobra
wing project discover ~/code --depth 2
wing project import ~/code --dry-run
```
