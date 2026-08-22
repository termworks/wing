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
