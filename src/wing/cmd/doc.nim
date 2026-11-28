## `wing doc` — a project's docs on the wing server: notes, designs, whatever is kept beside its
## tasks. The project is the one the current directory is in, as for `wing todo`.

import std/[base64, json, os, osproc, strutils]

import ../cliargs
import ../server
import ../ui
import ../util
import ./bundles
import ./todo

const DocKind = BundleKind(plural: "docs", noun: "doc", manifest: "README.md",
    starter: "# $name\n")

proc showDocHelp() =
  echo heading("wing doc", "a project's docs, on the wing server") & """


Usage: wing doc [COMMAND] [--project NAME]

  [list]                      the project's files
  show FILE                   a file, as it is written
  edit FILE                   a file in $EDITOR, saved back (a new path makes a new file)
  add LOCAL [AS]              upload a file of yours (as AS, or under its own name)
  rm FILE                     remove a file (a folder's path removes what is in it)
  open                        the project's docs in the browser
"""

proc docFiles(project: string): JsonNode =
  api("/docs/" & enc(project))

proc putFiles(project: string; files: JsonNode) =
  discard api("/docs/" & enc(project), "PUT", %*{"files": files})

proc handleDoc*(argsIn: seq[string]) =
  var args = argsIn
  if popFlag(args, ["-h", "--help"]):
    showDocHelp()
    return
  let command = if args.len == 0 or args[0].startsWith("-"): "list" else: args[0]
  if args.len > 0 and not args[0].startsWith("-"):
    args.delete(0)
  try:
    let project = currentProject(args)
    rejectUnknownOptions(args)
    case command
    of "list", "ls", "l":
      let bundle = api("/docs/" & enc(project) & "?meta=1")
      echo heading(project, $bundle["files"].len & " docs")
      for f in bundle["files"]:
        if f["path"].getStr().endsWith(".keep"):
          continue
        echo "  " & mute("·") & " " & f["path"].getStr().padRight(44) & mute(
            padLeft($f{"size"}.getInt() & " B", 9))
    of "show", "cat":
      requireArgs(args, 1, "wing doc show FILE")
      for f in docFiles(project)["files"]:
        if f["path"].getStr() == args[0]:
          stdout.write(base64.decode(f["data"].getStr()))
          return
      die("No doc " & args[0] & " in " & project)
    of "edit", "new":
      requireArgs(args, 1, "wing doc edit FILE")
      remoteEdit(DocKind, project, args[0])
    of "add", "upload":
      requireArgs(args, 1, "wing doc add LOCAL [AS]")
      if not fileExists(args[0]):
        die("No file " & args[0], 2)
      let target = if args.len > 1: args[1] else: extractFilename(args[0])
      var files = newJArray()
      for f in docFiles(project)["files"]:
        if f["path"].getStr() != target:
          files.add(f)
      files.add(%*{"path": target, "mode": 0o644, "data": base64.encode(
          readFile(args[0]))})
      putFiles(project, files)
      success("Added " & accent(target) & " to the docs of " & project)
    of "rm", "remove", "delete":
      requireArgs(args, 1, "wing doc rm FILE")
      var files = newJArray()
      var gone = 0
      for f in docFiles(project)["files"]:
        let path = f["path"].getStr()
        if path == args[0] or path.startsWith(args[0].strip(chars = {'/'}) & "/"):
          inc gone
        else:
          files.add(f)
      if gone == 0:
        die("No doc " & args[0] & " in " & project)
      putFiles(project, files)
      success("Removed " & $gone & " file" & (if gone == 1: "" else: "s"))
    of "open", "web":
      let url = loadServer().url & "/p/" & enc(project) & "/docs"
      if findExe("xdg-open").len > 0:
        discard startProcess("xdg-open", args = [url], options = {poUsePath, poDaemon})
      echo url
    else:
      die("Unknown doc command: " & command, 2)
  except ServerError as error:
    die(error.msg)
