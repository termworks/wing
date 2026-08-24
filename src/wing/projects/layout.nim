## Where a cloned project goes, and what it is called.
##
## A repository URL already says where it belongs -- host, owner, name -- so being asked for a path
## as well is being asked to repeat what was just typed. `ghq` made this its whole point, and the
## reason it works is that every machine ends up with the same layout: the path to a project is the
## same sentence on your laptop and on the build server, which is what makes a registry of projects
## across machines readable.

import std/[os, strutils]

type
  RepoRef* = object
    url*: string ## what to hand to git
    host*: string
    owner*: string
    name*: string

proc stripSuffix(value, suffix: string): string =
  if value.endsWith(suffix): value[0 ..< value.len - suffix.len] else: value

proc parseRepoRef*(reference: string): RepoRef =
  ## `git@github.com:user/repo.git`, `https://github.com/user/repo`, or `user/repo` for GitHub.
  var value = reference.strip()
  if value.len == 0:
    return

  if value.startsWith("git@") or (value.contains('@') and value.contains(
      ':') andnot value.contains("://")):
    # scp-style: user@host:owner/name
    let at = value.find('@')
    let colon = value.find(':')
    result.host = value[at + 1 ..< colon]
    let path = value[colon + 1 .. ^1].strip(chars = {'/'})
    let parts = path.split('/')
    result.owner = if parts.len > 1: parts[0 .. ^2].join("/") else: ""
    result.name = stripSuffix(parts[^1], ".git")
    result.url = value
    return

  # A repository on this filesystem has no host or owner to sort it under, so it goes in by name.
  # Without this, `file:///srv/git/repo.git` becomes a directory tree that spells out the whole
  # path, which is what the layout exists to avoid.
  if value.startsWith("file://") or value.startsWith("/") or
      value.startsWith("./") or value.startsWith("~"):
    result.url = value
    var path = value
    if path.startsWith("file://"):
      path = path[7 .. ^1]
    result.name = stripSuffix(path.strip(chars = {'/'}).lastPathPart, ".git")
    return

  if value.contains("://"):
    let withoutScheme = value.split("://", 1)[1]
    let parts = withoutScheme.strip(chars = {'/'}).split('/')
    if parts.len >= 2:
      result.host = parts[0]
      result.owner = parts[1 .. ^2].join("/")
      result.name = stripSuffix(parts[^1], ".git")
    result.url = value
    return

  # `owner/name`, which everybody writes and everybody means GitHub by.
  let parts = value.strip(chars = {'/'}).split('/')
  if parts.len >= 2:
    result.host = "github.com"
    result.owner = parts[0 .. ^2].join("/")
    result.name = stripSuffix(parts[^1], ".git")
    result.url = "https://github.com/" & result.owner & "/" & result.name & ".git"

proc codeRoot*(): string =
  ## Where clones land. `WING_CODE_ROOT` first, so a machine that keeps code somewhere else can say
  ## so once instead of at every clone.
  let configured = getEnv("WING_CODE_ROOT")
  if configured.len > 0:
    return configured
  getHomeDir() / "code"

proc layoutPath*(root: string; repo: RepoRef): string =
  ## `<root>/<host>/<owner>/<name>`, which is what makes two machines agree about where a project
  ## is without either of them being told.
  if repo.name.len == 0:
    return ""
  var path = root
  if repo.host.len > 0:
    path = path / repo.host
  if repo.owner.len > 0:
    path = path / repo.owner
  path / repo.name
