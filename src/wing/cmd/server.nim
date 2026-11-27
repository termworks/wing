## `wing server` — log in to a wing server and keep the projects registered there.

import std/[json, os, strutils]

import ../cliargs
import ../server
import ../store/projects
import ../util

proc showServerHelp() =
  echo """
Usage: wing server <COMMAND>

Commands:
  login URL --token TOKEN   remember the server and a token from its settings page
  logout                    forget them
  status                    where this machine is logged in, and whether it answers
  sync                      register every project of this machine on the server

The token is kept in """ & serverConfigPath() & """ (readable by you only).
WING_SERVER and WING_TOKEN override the saved login.
"""

proc handleServer*(argsIn: seq[string]) =
  var args = argsIn
  if args.len == 0 or popFlag(args, ["-h", "--help"]):
    showServerHelp()
    return
  let command = args[0]
  args.delete(0)
  case command
  of "login":
    var token = popValue(args, ["-t", "--token"])
    rejectUnknownOptions(args)
    requireArgs(args, 1, "wing server login URL --token TOKEN")
    var url = args[0].strip(chars = {'/', ' '}, leading = false)
    if not url.contains("://"):
      url = "https://" & url
    if token.len == 0:
      stdout.write("Token (from " & url & "/settings): ")
      token = stdin.readLine().strip()
    let config = ServerConfig(url: url, token: token)
    try:
      let found = config.request("GET", "/api/projects")
      saveServer(config)
      echo "Logged in to " & url & " (" & $found.len & " projects there)"
    except ServerError as error:
      die("Not saved: " & error.msg)
  of "logout":
    rejectUnknownOptions(args)
    removeFile(serverConfigPath())
    echo "Logged out"
  of "status", "st":
    rejectUnknownOptions(args)
    let config = loadServer()
    if not config.configured:
      echo "Not logged in to a wing server"
      return
    echo "Server: " & config.url
    try:
      let found = config.request("GET", "/api/projects")
      let open = config.request("GET", "/api/tasks?state=todo").len +
                 config.request("GET", "/api/tasks?state=doing").len
      echo "Projects: " & $found.len
      echo "Open tasks: " & $open
    except ServerError as error:
      die("Not answering: " & error.msg)
  of "sync", "push":
    rejectUnknownOptions(args)
    let local = parseProjects(ensureProjectsFile())
    if local.len == 0:
      echo "No projects registered on this machine"
      return
    if not loadServer().configured:
      die("Not logged in to a wing server; run `wing server login URL --token TOKEN`")
    registerProjects(local)
  else:
    die("Unknown server command: " & command, 2)
