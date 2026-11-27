import std/[base64, json, os, sequtils, strutils]

import ../src/wing/server
import ../src/wing/types
import test_support

# What is sent to a wing server, and what the CLI does when there is none to send it to. The
# server itself is tested beside it (services/wing in the nixos repository).

let scratch = "/tmp/wing-server-test"
resetDir(scratch)
putEnv("XDG_DATA_HOME", scratch / "data")
putEnv("WING_SERVER", "")
putEnv("WING_TOKEN", "")

block payload:
  let project = Project(name: "thing", namespace: "default", path: scratch, language: "nim",
                        tags: @["a"], description: "d")
  let body = projectPayload(project)
  doAssert body["name"].getStr() == "thing"
  doAssert not body.hasKey("namespace"), "the local default namespace is not a server namespace"
  doAssert body["tags"][0].getStr() == "a"
  doAssert body["checkout"]["path"].getStr() == scratch
  doAssert body["checkout"]["machine"].getStr() == thisMachine()
  let filed = projectPayload(Project(name: "x", namespace: "termworks", machine: "lab", path: "/srv/x"))
  doAssert filed["namespace"].getStr() == "termworks"
  doAssert filed["checkout"]["machine"].getStr() == "lab"
  doAssert not filed.hasKey("remotes"), "remotes of a checkout elsewhere are not read here"

block remotes:
  let repo = scratch / "repo"
  createDir(repo)
  discard checked("git -C " & quoteShell(repo) & " init -q && git -C " & quoteShell(repo) &
                  " remote add origin https://git.example/o/r.git")
  let found = gitRemotes(repo)
  doAssert found.len == 1 and found[0].name == "origin" and found[0].url == "https://git.example/o/r.git"
  doAssert gitRemotes(scratch / "nope").len == 0

block templateFolder:
  let dir = scratch / "tpl"
  createDir(dir / "base" / ".git")
  writeFile(dir / "template.lua", "x")
  writeFile(dir / "base" / "run.sh", "#!/bin/sh")
  setFilePermissions(dir / "base" / "run.sh", {fpUserRead, fpUserWrite, fpUserExec})
  writeFile(dir / "base" / ".git" / "HEAD", "skip me")
  var files: seq[string]
  for file in templatePayload(dir)["files"]:
    files.add(file["path"].getStr())
    if file["path"].getStr() == "base/run.sh":
      doAssert file["mode"].getInt() == 0o755
      doAssert base64.decode(file["data"].getStr()) == "#!/bin/sh"
  doAssert "template.lua" in files and "base/run.sh" in files
  doAssert files.allIt(".git" notin it), "a template's own git folder is not pushed"

block notLoggedIn:
  doAssert not loadServer().configured
  var raised = false
  try:
    discard api("/projects")
  except ServerError:
    raised = true
  doAssert raised

block environmentWins:
  putEnv("WING_SERVER", "https://wing.example/")
  putEnv("WING_TOKEN", "t")
  let config = loadServer()
  doAssert config.url == "https://wing.example" and config.token == "t" and config.host == "wing.example"
  putEnv("WING_SERVER", "")
  putEnv("WING_TOKEN", "")

# The commands, through the binary.
compileBinary()
let env = freshEnv("server")
let w = wing(env)

block cliWithoutServer:
  let todo = run(w & "todo --project x")
  doAssert todo.code != 0 and "not logged in" in todo.output, todo.output
  let login = run(w & "server login http://127.0.0.1:9 --token t")
  doAssert login.code != 0 and "Not saved" in login.output, login.output
  doAssert "Not logged in" in checked(w & "server status")
  let pull = run(w & "template pull")
  doAssert pull.code != 0, pull.output

block pulledTemplatesWin:
  # A pulled copy is the most specific root: it wins over the data root's own templates.
  let dataHome = "/tmp/wing-server-data"
  let pulled = dataHome / "wing" / "server" / "templates" / "same"
  let local = dataHome / "wing" / "templates" / "same"
  for dir in [pulled, local]:
    createDir(dir)
    writeFile(dir / "template.lua", "require(\"wing\").template(\"same\", { description = \"" &
              (if dir == pulled: "pulled" else: "local") & "\" })")
  let info = checked(w & "template info same")
  doAssert "pulled" in info, info

block noProvenanceFile:
  let dataHome = "/tmp/wing-server-data"
  let tpl = dataHome / "wing" / "server" / "templates" / "plain"
  createDir(tpl)
  writeFile(tpl / "template.lua", "require(\"wing\").template(\"plain\", { description = \"p\" })")
  writeFile(tpl / "README.md", "{{name}}")
  let target = scratch / "made"
  discard checked(w & "template apply plain " & quoteShell(target) & " --no-git")
  doAssert readFile(target / "README.md") == "made"
  doAssert not fileExists(target / ".wing.toml"), "generated projects carry no wing file"

echo "server ok"
