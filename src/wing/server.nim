## The client of a wing server (wing.bresilla.com): projects, their tasks and plans, and the
## templates projects are made from, over its JSON /api with a token made on its settings page.
##
## Requests go through curl rather than Nim's httpclient: the release binary is static musl and
## links no TLS library, and curl is on every machine this runs on.

import std/[base64, json, os, osproc, streams, strutils, times, uri]

import ./storage
import ./types

type
  ServerConfig* = object
    url*: string
    token*: string

  ServerError* = object of CatchableError

proc serverConfigPath*(): string =
  dataRoot() / "server.json"

proc loadServer*(): ServerConfig =
  ## The saved login, overridden by WING_SERVER and WING_TOKEN when they are set.
  let path = serverConfigPath()
  if fileExists(path):
    try:
      let node = parseFile(path)
      result.url = node{"url"}.getStr()
      result.token = node{"token"}.getStr()
    except CatchableError:
      discard
  if getEnv("WING_SERVER").len > 0:
    result.url = getEnv("WING_SERVER")
  if getEnv("WING_TOKEN").len > 0:
    result.token = getEnv("WING_TOKEN")
  result.url = result.url.strip(chars = {'/', ' '}, leading = false)

proc saveServer*(config: ServerConfig) =
  let path = serverConfigPath()
  writeFile(path, $(%*{"url": config.url, "token": config.token}) & "\n")
  setFilePermissions(path, {fpUserRead, fpUserWrite})

proc configured*(config: ServerConfig): bool =
  config.url.len > 0 and config.token.len > 0

proc host*(config: ServerConfig): string =
  parseUri(config.url).hostname

proc quoteConfig(value: string): string =
  "\"" & value.replace("\\", "\\\\").replace("\"", "\\\"") & "\""

proc request*(config: ServerConfig; meth, path: string; body: JsonNode = nil;
    timeout = 30): JsonNode =
  ## One call to the server's API. The token goes to curl on stdin, so it is never in argv.
  if not config.configured:
    raise newException(ServerError, "not logged in to a wing server; run `wing server login URL --token TOKEN`")
  var args = @["-sS", "-X", meth, "--max-time", $timeout, "-K", "-", "-w", "\n%{http_code}",
               "-H", "Accept: application/json"]
  var bodyFile = ""
  if body != nil:
    bodyFile = getTempDir() / ("wing-request-" & $getCurrentProcessId() & ".json")
    writeFile(bodyFile, $body)
    args.add(@["-H", "Content-Type: application/json", "--data-binary", "@" & bodyFile])
  let process = startProcess("curl", args = args, options = {poUsePath, poStdErrToStdOut})
  try:
    let input = process.inputStream()
    input.write("header = " & quoteConfig("Authorization: Bearer " & config.token) & "\n")
    input.write("url = " & quoteConfig(config.url & path) & "\n")
    input.close()
    let output = process.outputStream().readAll()
    let exitCode = process.waitForExit()
    if exitCode != 0:
      raise newException(ServerError, "could not reach " & config.url & ": " & output.strip())
    let cut = output.rfind('\n')
    let code = output[cut + 1 .. ^1].strip()
    let text = if cut > 0: output[0 ..< cut] else: ""
    var parsed: JsonNode = newJNull()
    if text.strip().len > 0:
      try:
        parsed = parseJson(text)
      except CatchableError:
        raise newException(ServerError, config.url & " answered " & code & " with something that is not JSON")
    if not code.startsWith("2"):
      let said = if parsed.kind == JObject: parsed{"error"}.getStr() else: ""
      raise newException(ServerError, (if said.len > 0: said else: config.url & " answered " & code))
    parsed
  finally:
    process.close()
    if bodyFile.len > 0:
      removeFile(bodyFile)

proc api*(path: string; meth = "GET"; body: JsonNode = nil): JsonNode =
  loadServer().request(meth, "/api" & path, body)

proc enc*(part: string): string =
  encodeUrl(part, usePlus = false)

# --- Projects ------------------------------------------------------------------------------

proc gitRemotes*(path: string): seq[tuple[name, url: string]] =
  ## A checkout's remotes, the fetch side of each, in the order git lists them.
  if path.len == 0 or not dirExists(path / ".git") and not fileExists(path / ".git"):
    return
  let (output, code) = execCmdEx("git -C " & quoteShell(path) & " remote -v")
  if code != 0:
    return
  for line in output.splitLines():
    let fields = line.splitWhitespace()
    if fields.len >= 3 and fields[2] == "(fetch)":
      result.add((fields[0], fields[1]))

proc thisMachine*(): string =
  ## This machine's name, as the server lists where a project is checked out.
  try:
    result = readFile("/proc/sys/kernel/hostname").strip()
  except IOError:
    result = getEnv("HOSTNAME")

proc projectPayload*(project: Project): JsonNode =
  result = %*{"name": project.name}
  if project.namespace.len > 0 and project.namespace != "default":
    result["namespace"] = %project.namespace
  if project.description.len > 0:
    result["description"] = %project.description
  if project.language.len > 0:
    result["language"] = %project.language
  if project.tags.len > 0:
    result["tags"] = %project.tags
  if project.path.len > 0:
    let machine = if project.machine.len > 0: project.machine else: thisMachine()
    if machine.len > 0:
      result["checkout"] = %*{"machine": machine, "path": project.path}
  if project.machine.len == 0:
    let remotes = gitRemotes(project.path)
    if remotes.len > 0:
      var list = newJArray()
      for remote in remotes:
        list.add(%*{"name": remote.name, "url": remote.url})
      result["remotes"] = list

proc registerProjects*(projects: openArray[Project]; quiet = false) =
  ## Tell the server about projects, if this machine is logged in to one. A server that is down
  ## is worth a warning, never a failed command: the local registry already has them.
  let config = loadServer()
  if not config.configured:
    return
  var done = 0
  for project in projects:
    try:
      discard config.request("POST", "/api/projects", projectPayload(project))
      inc done
    except ServerError as error:
      stderr.writeLine("wing: could not register '" & project.name & "' on " & config.host & ": " & error.msg)
  if done > 0 and not quiet:
    echo "Registered " & (if done == 1: "'" & projects[0].name & "'" else: $done & " projects") & " on " & config.host

proc registerProject*(project: Project; quiet = false) =
  registerProjects([project], quiet)

# --- Templates -----------------------------------------------------------------------------

proc serverTemplatesRoot*(): string =
  ## Where pulled templates live: one more template root, the most specific one.
  dataRoot() / "server" / "templates"

proc pullStatePath(): string =
  dataRoot() / "server" / "templates.json"

proc readPullState(): JsonNode =
  try:
    result = parseFile(pullStatePath())
  except CatchableError:
    result = %*{"pulled": 0, "hashes": {}}

proc pullTemplates*(force = false): tuple[changed, removed, kept: int] =
  ## Mirror the server's templates into serverTemplatesRoot(): fetch what changed, drop what the
  ## server no longer has. Each template is written beside its old copy and swapped in whole.
  let config = loadServer()
  let listing = config.request("GET", "/api/templates")
  let root = serverTemplatesRoot()
  createDir(root)
  var state = readPullState()
  let previous = state{"hashes"}
  var hashes = newJObject()
  var wanted: seq[string]
  for entry in listing:
    let name = entry["name"].getStr()
    let hash = entry["hash"].getStr()
    if name.len == 0 or name.contains('/') or name.startsWith("."):
      continue
    wanted.add(name)
    hashes[name] = %hash
    if not force and previous != nil and previous{name}.getStr() == hash and dirExists(root / name):
      inc result.kept
      continue
    let full = config.request("GET", "/api/templates/" & enc(name))
    let staging = root / ("." & name & ".new")
    removeDir(staging)
    createDir(staging)
    for file in full["files"]:
      let rel = file["path"].getStr()
      if rel.len == 0 or rel.startsWith("/") or ".." in rel.split('/'):
        continue
      let target = staging / rel
      createDir(parentDir(target))
      writeFile(target, base64.decode(file["data"].getStr()))
      let mode = file{"mode"}.getInt(0o644)
      var perms = {fpUserRead, fpUserWrite, fpGroupRead, fpOthersRead}
      if (mode and 0o111) != 0:
        perms.incl({fpUserExec, fpGroupExec, fpOthersExec})
      setFilePermissions(target, perms)
    removeDir(root / name)
    moveDir(staging, root / name)
    inc result.changed
  for kind, path in walkDir(root):
    let name = extractFilename(path)
    if kind == pcDir and not name.startsWith(".") and name notin wanted:
      removeDir(path)
      inc result.removed
  state["hashes"] = hashes
  state["pulled"] = %getTime().toUnix()
  writeFile(pullStatePath(), $state)

proc pullIfStale*(maxAge = 600) =
  ## Keep the pulled templates fresh without making every command wait on the network.
  let config = loadServer()
  if not config.configured or getEnv("WING_TEMPLATE_DIR").len > 0:
    return
  let last = readPullState(){"pulled"}.getBiggestInt(0)
  if getTime().toUnix() - last < maxAge:
    return
  try:
    discard pullTemplates()
  except CatchableError as error:
    stderr.writeLine("wing: templates not refreshed from " & config.host & ": " & error.msg)

proc templatePayload*(dir: string): JsonNode =
  ## Every file under a template folder, as the server stores them.
  var files = newJArray()
  for rel in walkDirRec(dir, relative = true, skipSpecial = true):
    let full = dir / rel
    if symlinkExists(full):
      continue
    let parts = rel.split(DirSep)
    if ".git" in parts:
      continue
    var mode = 0o644
    if fpUserExec in getFilePermissions(full):
      mode = 0o755
    files.add(%*{"path": parts.join("/"), "mode": mode, "data": base64.encode(readFile(full))})
  %*{"files": files}

proc pushTemplate*(name, dir: string): JsonNode =
  api("/templates/" & enc(name), "PUT", templatePayload(dir))

# --- Tasks and plans -----------------------------------------------------------------------

proc projectTasks*(project: string; state = ""): JsonNode =
  api("/projects/" & enc(project) & "/tasks" & (if state.len > 0: "?state=" & enc(state) else: ""))

proc allTasks*(state = ""): JsonNode =
  api("/tasks" & (if state.len > 0: "?state=" & enc(state) else: ""))

proc addTask*(project, text: string; fields: JsonNode = nil): JsonNode =
  var body = if fields == nil: newJObject() else: fields
  body["quick"] = %text
  api("/projects/" & enc(project) & "/tasks", "POST", body)

proc changeTask*(project: string; number: int; fields: JsonNode): JsonNode =
  api("/projects/" & enc(project) & "/tasks/" & $number, "PATCH", fields)

proc removeTask*(project: string; number: int) =
  discard api("/projects/" & enc(project) & "/tasks/" & $number, "DELETE")

proc getTask*(project: string; number: int): JsonNode =
  api("/projects/" & enc(project) & "/tasks/" & $number)

proc projectPlans*(project: string): JsonNode =
  api("/projects/" & enc(project) & "/plans")

proc getPlan*(project: string; number: int): JsonNode =
  api("/projects/" & enc(project) & "/plans/" & $number)

proc addPlan*(project, title, notes: string): JsonNode =
  api("/projects/" & enc(project) & "/plans", "POST", %*{"title": title, "notes": notes})

proc changePlan*(project: string; number: int; fields: JsonNode): JsonNode =
  api("/projects/" & enc(project) & "/plans/" & $number, "PATCH", fields)

proc removePlan*(project: string; number: int) =
  discard api("/projects/" & enc(project) & "/plans/" & $number, "DELETE")

proc serverProject*(project: string): JsonNode =
  api("/projects/" & enc(project))

proc serverProjects*(): JsonNode =
  api("/projects")
