## `wing server` — log in to a wing server, see its projects, and keep this machine's there.

import std/[json, os, osproc, strutils, terminal]

import ../cliargs
import ../server
import ../store/projects
import ../ui
import ../util

proc showServerHelp() =
  echo heading("wing server", "the wing server this machine works with") &
      """


Usage: wing server <COMMAND>

Commands:
  login URL [--token TOKEN]   remember the server and a token from its settings page
                              (without --token, it asks for one)
  logout                      forget them
  status                      where this machine is logged in, and what is there
  projects [--json]           every project on the server, with version, build and tasks
  import [OWNER/REPO...]      register repositories from its git host (none: list them)
  sync                        register every project of this machine on the server
  open [PROJECT]              the server's page (a project's, if named) in the browser

The token is kept in """ & serverConfigPath() & """ (readable by you only).
WING_SERVER and WING_TOKEN override the saved login.
"""

proc needLogin(): ServerConfig =
  result = loadServer()
  if not result.configured:
    die("Not logged in to a wing server; run `wing server login URL`")

proc openUrl(url: string) =
  let opener = if findExe("xdg-open").len > 0: "xdg-open" elif findExe(
      "open").len > 0: "open" else: ""
  if opener.len == 0 or not isatty(stdout):
    echo url
    return
  discard startProcess(opener, args = [url], options = {poUsePath, poDaemon})
  notice("Opened " & url)

proc handleServer*(argsIn: seq[string]) =
  var args = argsIn
  if args.len == 0 or popFlag(args, ["-h", "--help"]):
    showServerHelp()
    return
  let command = args[0]
  args.delete(0)
  try:
    case command
    of "login":
      var token = popValue(args, ["-t", "--token"])
      rejectUnknownOptions(args)
      requireArgs(args, 1, "wing server login URL [--token TOKEN]")
      var url = args[0].strip(chars = {'/', ' '}, leading = false)
      if not url.contains("://"):
        url = "https://" & url
      if token.len == 0:
        # Asked for, and not echoed: a token typed into a terminal should not stay on the screen.
        stdout.write(accent("? ") & "Token " & mute("(make one at " & url &
            "/settings)") & ": ")
        flushFile(stdout)
        if isatty(stdin):
          token = readPasswordFromStdin("").strip()
          echo ""
        else:
          token = stdin.readLine().strip()
        if token.len == 0:
          die("No token given", 2)
      let config = ServerConfig(url: url, token: token)
      try:
        let found = config.request("GET", "/api/projects")
        saveServer(config)
        success("Logged in to " & accent(config.host) & mute("  " & $found.len &
            " projects there"))
      except ServerError as error:
        die("Not saved: " & error.msg)
    of "logout":
      rejectUnknownOptions(args)
      removeFile(serverConfigPath())
      success("Logged out")
    of "status", "st":
      rejectUnknownOptions(args)
      let config = loadServer()
      if not config.configured:
        echo heading("Not logged in", "wing server login URL")
        return
      try:
        let found = config.request("GET", "/api/projects")
        let todo = config.request("GET", "/api/tasks?state=todo").len
        let doing = config.request("GET", "/api/tasks?state=doing").len
        let templates = config.request("GET", "/api/templates").len
        let skills = config.request("GET", "/api/skills").len
        echo heading(config.host, "logged in")
        echo facts([("server", config.url), ("projects", $found.len),
                    ("tasks", $(todo + doing) & " open · " & $doing &
                        " doing"),
                    ("templates", $templates), ("skills", $skills),
                    ("this machine", thisMachine())])
      except ServerError as error:
        die("Not answering: " & error.msg)
    of "projects", "ls", "list":
      let asJson = popFlag(args, ["--json"])
      rejectUnknownOptions(args)
      let config = needLogin()
      let found = config.request("GET", "/api/projects?summary=1")
      if asJson:
        echo found.pretty
        return
      echo heading("Projects on " & config.host, $found.len & " registered")
      var rows: seq[seq[string]]
      for p in found:
        let ns = p{"namespace"}.getStr()
        let tasks = p{"doing"}.getInt() + p{"todo"}.getInt()
        rows.add(@[p["name"].getStr(), (if ns.len > 0: mute(ns) else: ""), p{"version"}.getStr(),
                   buildBadge(p{"build"}.getStr()),
                   (if tasks > 0: $tasks & " open" & (if p{"doing"}.getInt() >
                       0: warning(" · " & $p{"doing"}.getInt() &
                       " doing") else: "") else: mute("—")),
                   mute(ago(p{"pushed"}.getStr()))])
      if rows.len > 0:
        echo table(@["Project", "Namespace", "Version", "Build", "Tasks",
            "Pushed"], rows)
    of "import":
      rejectUnknownOptions(args)
      let config = needLogin()
      if args.len == 0:
        let open = config.request("GET", "/api/import")
        echo heading("On git, not registered yet", $open.len & " repositories")
        for r in open:
          echo "  " & r["repo"].getStr().padRight(32) & "  " & mute(clip(r[
              "description"].getStr(), 60))
        if open.len > 0:
          echo ""
          notice("Register some with: wing server import OWNER/REPO...")
        return
      let made = config.request("POST", "/api/import", %*{"repos": args})
      if made["imported"].len == 0:
        caution("Nothing imported: already registered, or not on the server's git host")
      for name in made["imported"]:
        success("Imported " & accent(name.getStr()))
    of "sync", "push":
      rejectUnknownOptions(args)
      discard needLogin()
      let local = parseProjects(ensureProjectsFile())
      if local.len == 0:
        notice("No projects registered on this machine")
        return
      registerProjects(local)
    of "open", "web":
      rejectUnknownOptions(args)
      let config = needLogin()
      openUrl(config.url & (if args.len > 0: "/p/" & enc(args[0]) else: "/"))
    else:
      die("Unknown server command: " & command, 2)
  except ServerError as error:
    die(error.msg)
