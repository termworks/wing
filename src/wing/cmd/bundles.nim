## What `wing template` and `wing skill` share: listing, making, showing, editing and removing
## them on the wing server. Edits go through a scratch copy: pulled, opened in $EDITOR, pushed.

import std/[json, os, osproc, strutils]

import ../cliargs
import ../server
import ../ui
import ../util

type BundleKind* = object
  plural*: string   # "templates" or "skills"
  noun*: string     # "template" or "skill"
  manifest*: string # the file that says what it is
  starter*: string  # what a new one starts with; $name and $description are filled in

proc starterFor(kind: BundleKind; name, description: string): string =
  kind.starter.replace("$name", name).replace("$description",
      if description.len > 0: description else: "What it does, and when to use it")

proc remoteList*(kind: BundleKind) =
  let found = listBundles(kind.plural)
  echo heading(kind.plural.capitalizeAscii() & " on " & loadServer().host, $found.len)
  var rows: seq[seq[string]]
  for b in found:
    rows.add(@[b["name"].getStr(), $b["files"].getInt(), mute(ago(b["updated"].getStr())),
               clip(b["description"].getStr(), 70)])
  if rows.len > 0:
    echo table(@[kind.noun.capitalizeAscii(), "Files", "Updated",
        "Description"], rows)

proc remoteShow*(kind: BundleKind; name: string) =
  let b = getBundle(kind.plural, name)
  echo ""
  echo "  " & accent("◆ ") & strong(name) & "  " & mute(kind.noun & " on " &
      loadServer().host)
  if b["description"].getStr().len > 0:
    echo "  " & b["description"].getStr()
  echo ""
  for file in b["files"]:
    let size = file{"size"}.getInt()
    let exec = if (file{"mode"}.getInt() and 0o111) != 0: "  " & badge("exec",
        "mute") else: ""
    echo "  " & mute("·") & " " & file["path"].getStr().padRight(48) & mute(
        padLeft($size & " B", 9)) & exec
  echo ""

proc remoteNew*(kind: BundleKind; name, description: string) =
  var exists = false
  try:
    discard getBundle(kind.plural, name)
    exists = true
  except ServerError:
    discard
  if exists:
    die("There is already a " & kind.noun & " named " & name, 2)
  let dir = getTempDir() / ("wing-new-" & $getCurrentProcessId()) / name
  createDir(dir)
  writeFile(dir / kind.manifest, starterFor(kind, name, description))
  discard pushBundle(kind.plural, name, dir)
  removeDir(parentDir(dir))
  success("Made " & kind.noun & " " & accent(name) & mute("  edit it: wing " &
      kind.noun & " edit " & name))

proc remoteRemove*(kind: BundleKind; name: string; yes: bool) =
  if not yes:
    let host = loadServer().host
    let question = "Delete the $1 $2 from $3 for every machine? [y/N] " % [
        kind.noun, strong(name), host]
    stdout.write(warning("? ") & question)
    flushFile(stdout)
    let answer = try: stdin.readLine().strip().toLowerAscii() except EOFError: ""
    if answer notin ["y", "yes"]:
      notice("Kept " & name)
      return
  deleteBundle(kind.plural, name)
  success("Deleted " & kind.noun & " " & name)

proc remoteEdit*(kind: BundleKind; name, file: string) =
  ## One file of a template or skill in $EDITOR; the whole folder goes back when it changed.
  let b = getBundle(kind.plural, name)
  let dir = getTempDir() / ("wing-edit-" & $getCurrentProcessId()) / name
  writeBundle(b, dir)
  let rel = if file.len > 0: file else: kind.manifest
  if rel.startsWith("/") or ".." in rel.split('/'):
    die("Not a file inside the " & kind.noun & ": " & rel, 2)
  let target = dir / rel
  createDir(parentDir(target))
  let before = if fileExists(target): readFile(target) else: ""
  if not fileExists(target):
    writeFile(target, "")
  let editor = block:
    let chosen = getEnv("VISUAL", getEnv("EDITOR"))
    if chosen.len > 0: chosen else: "vi"
  if execShellCmd(editor & " " & quoteShell(target)) != 0:
    removeDir(parentDir(dir))
    die("The editor did not finish; nothing was changed")
  if readFile(target) == before:
    notice("No change to " & rel)
  else:
    discard pushBundle(kind.plural, name, dir)
    success("Saved " & accent(name & "/" & rel) & " to " & loadServer().host)
  removeDir(parentDir(dir))

proc bundleCommand*(kind: BundleKind; command: string; args: seq[string];
    yes = false): bool =
  ## The shared commands; false when `command` is not one of them.
  try:
    case command
    of "remote", "server":
      remoteList(kind)
    of "show", "cat":
      requireArgs(args, 1, "wing " & kind.noun & " show NAME")
      remoteShow(kind, args[0])
    of "new", "create":
      requireArgs(args, 1, "wing " & kind.noun & " new NAME [DESCRIPTION...]")
      remoteNew(kind, args[0], args[1 .. ^1].join(" "))
    of "delete", "rm-server":
      requireArgs(args, 1, "wing " & kind.noun & " delete NAME")
      remoteRemove(kind, args[0], yes)
    of "edit":
      requireArgs(args, 1, "wing " & kind.noun & " edit NAME [FILE]")
      remoteEdit(kind, args[0], if args.len > 1: args[1] else: "")
    else:
      return false
  except ServerError as error:
    die(error.msg)
  true
