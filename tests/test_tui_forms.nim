import std/[os, strutils]

import ../src/wing/tui/forms
import ../src/wing/tui/render

let missingProject = projectFormCommand("", "/tmp/demo", "default", "Nim", "", "")
doAssert not missingProject.ok
doAssert missingProject.error.contains("project name")

let project = projectFormCommand("demo", "/tmp/demo", "", "Nim", "bobabrew",
    "cli,tui")
doAssert project.ok
doAssert project.command.contains("project --namespace default add demo")
doAssert project.command.contains("--language Nim")
doAssert project.command.contains("--framework bobabrew")
doAssert project.command.contains("--tags cli")
doAssert project.command.contains("--tags tui")

let machine = machineFormCommand("lab", "tester", "/tmp/key",
    "127.0.0.1:22:local")
doAssert machine.ok
doAssert machine.command.contains("machine add lab 127.0.0.1:22:local")
doAssert machine.command.contains("--username tester")
doAssert machine.command.contains("--key /tmp/key")

let missingTemplatePath = templateFormCommand("base", "desc",
    "/tmp/wing-tui-missing-template", "Nim", "")
doAssert not missingTemplatePath.ok
doAssert missingTemplatePath.error.contains("does not exist")

let templatePath = "/tmp/wing-tui-form-template"
removeDir(templatePath)
createDir(templatePath)
let templateCommand = templateFormCommand("base", "desc", templatePath, "Nim",
    "cli")
doAssert templateCommand.ok
doAssert templateCommand.command.contains("template add base")
doAssert templateCommand.command.contains("--description desc")
doAssert templateCommand.command.contains("--path " & templatePath)
doAssert templateCommand.command.contains("--language Nim")
doAssert templateCommand.command.contains("--framework cli")

doAssert overlayScroll(0, 100, -1) == 0
doAssert overlayScroll(0, 100, 10) == 10
doAssert overlayScroll(95, 100, 10) == 99
doAssert overlayScroll(5, 0, 1) == 0

# --- the host views ------------------------------------------------------------
# The renderer reads columns by position, so a section's layout and its row rendering have to agree.
# They disagreed once already: the Projects columns gained a host and every row was labelled with
# the wrong field until this was checked.
import ../src/wing/types

let hostsSection = DashboardSection(title: "Hosts",
    headers: @["Host", "Projects", "Languages", "OS"])
let busyHost = rowParts(hostsSection, @["lab", "8", "go, nim", "Debian 13"])
doAssert busyHost.name == "lab", busyHost.name
doAssert busyHost.right == "8 projects", busyHost.right
doAssert busyHost.meta == "go, nim", busyHost.meta
doAssert busyHost.desc == "Debian 13", busyHost.desc

# A machine with projects but no languages detected is not an empty machine.
let quietHost = rowParts(hostsSection, @["lab", "3", "", ""])
doAssert not quietHost.meta.contains("nothing"), quietHost.meta
let emptyHost = rowParts(hostsSection, @["box", "0", "", ""])
doAssert emptyHost.meta.contains("nothing registered"), emptyHost.meta

let projectsSection = DashboardSection(title: "Projects",
    headers: @["Host", "Name", "Path", "Language"])
let projectRow = rowParts(projectsSection, @["lab", "api", "/srv/api", "go"])
doAssert projectRow.name == "api", "the row is named for the project, not the host"
doAssert projectRow.meta == "on lab", projectRow.meta
doAssert projectRow.desc == "/srv/api", projectRow.desc
doAssert projectRow.right == "go", projectRow.right

let machinesSection = DashboardSection(title: "Machines",
    headers: @["Name", "User", "Hosts", "Tags", "OS"])
let machineRow = rowParts(machinesSection, @["lab", "tester",
    "10.0.0.1:22:local", "gpu", "Ubuntu 26.04"])
doAssert machineRow.name == "lab"
doAssert machineRow.desc.contains("Ubuntu 26.04"), machineRow.desc
doAssert machineRow.desc.contains("gpu"), machineRow.desc

# Every section the dashboard builds needs an icon and a row shape, or it renders as the fallback.
for title in ["Hosts", "Projects", "Machines", "Templates", "Sync"]:
  doAssert sectionIcon(title) != "•", title & " should have an icon of its own"
