## Where a template comes from, and what it hashed to when it arrived.
##
## Modelled on oslo's plugin sources. A template is a directory somebody else wrote, so installing
## one is fetching code and deciding whether to trust it — the same problem, answered the same way.

import std/[algorithm, md5, os, strutils]

type
  SourceKind* = enum
    skPath, skGit

  Source* = object
    ## Parsed from the word after `wing template install`.
    case kind*: SourceKind
    of skPath:
      path*: string
    of skGit:
      url*: string
      revision*: string

  SourceError* = object of CatchableError


proc parseSource*(word: string): Source =
  ## `github:user/repo@rev`, an https/ssh/file URL with `@rev`, or a directory on this machine.
  ##
  ## **The revision is not optional for a git source.** Without one, `install` takes whatever the
  ## branch says today and something else tomorrow, and the trust hash then refuses to load it the
  ## morning after every upstream commit -- which teaches people to run `allow` without reading,
  ## and that is worse than having no gate at all.
  var remote = ""
  if word.startsWith("github:"):
    remote = "https://github.com/" & word["github:".len .. ^1]
  elif word.startsWith("https://") or word.startsWith("git@") or
      word.startsWith("ssh://") or word.startsWith("file://"):
    # `file://` is a git URL like any other, and it is how a local mirror or a repository on a
    # shared disk is installed -- pinned to a revision the same way a remote one is.
    remote = word

  if remote.len == 0:
    if dirExists(word):
      return Source(kind: skPath, path: absolutePath(word))
    raise newException(SourceError, word & ": not a directory, and not a git URL")

  # `git@github.com:user/repo` carries an `@` that is not a revision separator, so the split is
  # from the right and the tail must not look like part of a path.
  let at = remote.rfind('@')
  if at <= 0:
    raise newException(SourceError,
        word & ": name a revision, as in github:user/repo@<commit-or-tag>")
  let url = remote[0 ..< at]
  let revision = remote[at + 1 .. ^1]
  if revision.len == 0 or revision.contains('/') or url.len == 0:
    raise newException(SourceError,
        word & ": name a revision, as in github:user/repo@<commit-or-tag>")
  Source(kind: skGit, url: url, revision: revision)

proc describe*(source: Source): string =
  case source.kind
  of skPath: source.path
  of skGit: source.url & "@" & source.revision

proc luaFiles*(dir: string): seq[string] =
  ## Every `.lua` file under `dir`, relative and sorted.
  ##
  ## Only `.lua` is hashed. Editing a README is not a change to what a template will do, and
  ## hashing it would make every documentation edit a refusal to run.
  for path in walkDirRec(dir, relative = true):
    if path.endsWith(".lua"):
      result.add(path)
  result.sort()

proc hashTemplate*(dir: string): string =
  ## What this template's code hashes to. Paths are hashed alongside contents, so moving logic from
  ## one file to another is a change even when the bytes are the same.
  var ctx: MD5Context
  ctx.md5Init()
  for rel in luaFiles(dir):
    ctx.md5Update(rel, rel.len)
    let body = readFile(dir / rel)
    ctx.md5Update(body, body.len)
  var digest: MD5Digest
  ctx.md5Final(digest)
  $digest
