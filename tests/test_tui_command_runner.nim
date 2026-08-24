import std/[os, strutils]

import test_support

compileBinary()

let envPrefix = freshEnv("tui-command")
let wing = wing(envPrefix)

let emptySnapshot = checked(wing & "tui --snapshot")
doAssert emptySnapshot.contains("wing tui")
doAssert emptySnapshot.contains("Projects:")

discard checked(wing & "tui --command " &
    quoteShell("project add tui_demo --path /tmp/tui_demo --language go"))

let populatedSnapshot = checked(wing & "tui --snapshot")
doAssert populatedSnapshot.contains("Projects: 1")

let blockedNested = run(wing & "tui --command " & quoteShell("tui --snapshot"))
doAssert blockedNested.code != 0
doAssert blockedNested.output.contains("Nested TUI commands")

let blockedSsh = run(wing & "tui --command " & quoteShell(
    "machine connect lab"))
doAssert blockedSsh.code != 0
doAssert blockedSsh.output.contains("Interactive ssh is disabled")

import ../src/wing/types
import ../src/wing/tui/commands

# --- the commands the host views drive ----------------------------------------
# Rows are read by position here too: a Projects row is [host, name, ...], so the command has to
# qualify the name with the host or it acts on a project that happens to share a name.
let projectsView = DashboardSection(title: "Projects",
    headers: @["Host", "Name", "Path", "Language"])
let projectRow = @["lab", "api", "/srv/api", "go"]
doAssert infoCommand(projectsView, projectRow) == "project info lab:api",
    infoCommand(projectsView, projectRow)
doAssert deleteCommand(projectsView, projectRow) == "project remove lab:api",
    deleteCommand(projectsView, projectRow)

let hostsView = DashboardSection(title: "Hosts",
    headers: @["Host", "Projects", "Languages", "OS"])
doAssert infoCommand(hostsView, @["lab", "8", "", ""]) == "machine info lab"

# A row with only a host and no project name cannot be acted on, and must not build half a command.
doAssert infoCommand(projectsView, @["lab"]) == ""
doAssert deleteCommand(projectsView, @[]) == ""
