import std/[os, osproc, strutils]

import test_support

compileBinary()

# A template that is more than a pile of files: it decides what to write based on the machine it
# is running on. This is the whole point of the plugin shape.
let srcRoot = "/tmp/wing-plugin-src"
let cfgHome = "/tmp/wing-plugin-config"
resetDir(srcRoot)
resetDir(cfgHome)

writeFile(srcRoot / "template.lua", """
local wing = require("wing")
wing.template("thinker", {
  description = "a template that thinks before it writes",
  language = "text",
  tags = { "demo" },
})
""")
writeFile(srcRoot / "init.lua", """
local wing = require("wing")

wing.on.check(function(ctx)
  if not wing.sys.has("definitely-not-a-real-command") then
    wing.warn("that tool is missing, so its config is left out")
  end
end)

wing.on.file(function(file)
  if file.rel == "needs-tool.conf" then
    return { skip = true }
  end
end)
""")
writeFile(srcRoot / "README.md", "hello {{project_name}}")
writeFile(srcRoot / "needs-tool.conf", "this should never be written")

let envPrefix = freshEnv("plugin") & "XDG_CONFIG_HOME=" & quoteShell(cfgHome) & " "
let wing = wing(envPrefix)
discard checked(wing & "init")

# --- installing shows what it declares, before it is kept ----------------------
let installed = checked(wing & "template install " & quoteShell(srcRoot) & " --yes")
doAssert installed.contains("thinker"), installed
doAssert installed.contains("a template that thinks"), installed
# The manifest is read without the template's logic, so a candidate is a claim rather than the
# result of running it -- but a template that carries logic says so.
doAssert installed.contains("init.lua"), installed
doAssert installed.contains("Installed 'thinker'"), installed

let listed = checked(wing & "template installed")
doAssert listed.contains("thinker"), listed
doAssert listed.contains("ok"), listed

# --- installing registers it, so it is usable straight away --------------------
let target = "/tmp/wing-plugin-out"
removeDir(target)
let applied = checked(wing & "template apply thinker " & quoteShell(target) &
    " --name demo_thing")
doAssert applied.contains("successfully applied"), applied

# The check ran and warned.
doAssert applied.contains("that tool is missing"), applied
# The file filter left one out.
doAssert not fileExists(target / "needs-tool.conf"),
    "wing.on.file should have skipped that file"
doAssert readFile(target / "README.md").contains("hello demo_thing")
# A template's manifest and its logic describe the template; neither belongs in the output.
doAssert not fileExists(target / "template.lua")
doAssert not fileExists(target / "init.lua")

# --- the trust gate notices a change and `allow` accepts it --------------------
let installedDir = "/tmp/wing-plugin-data" / "wing" / "templates" / "thinker"
doAssert dirExists(installedDir), installedDir
writeFile(installedDir / "init.lua",
    readFile(installedDir / "init.lua") & "\n-- changed after install\n")
let changed = checked(wing & "template installed")
doAssert changed.contains("CHANGED"), changed
discard checked(wing & "template allow thinker")
let allowed = checked(wing & "template installed")
doAssert not allowed.contains("CHANGED"), allowed

# --- a source has to be a directory or a git URL with a revision ---------------
let noRevision = run(wing & "template install github:someone/repo")
doAssert noRevision.code != 0
doAssert noRevision.output.contains("name a revision"), noRevision.output

let notASource = run(wing & "template install /tmp/wing-plugin-does-not-exist")
doAssert notASource.code != 0
doAssert notASource.output.contains("not a directory"), notASource.output

# --- installing from a real repository, pinned to a revision -------------------
let repo = "/tmp/wing-plugin-repo"
resetDir(repo)
writeFile(repo / "template.lua", """
local wing = require("wing")
wing.template("fromgit", { description = "came from git", language = "text" })
""")
writeFile(repo / "file.txt", "{{project_name}} from git")
for command in ["git init -q", "git config user.email t@t", "git config user.name t",
                "git add -A", "git commit -qm seed"]:
  doAssert execCmdEx("cd " & quoteShell(repo) & " && " & command).exitCode == 0, command
let revision = execCmdEx("git -C " & quoteShell(repo) &
    " rev-parse HEAD").output.strip()

let fromGit = checked(wing & "template install " &
    quoteShell("file://" & repo & "@" & revision) & " --yes")
doAssert fromGit.contains("Installed 'fromgit'"), fromGit

let gitTarget = "/tmp/wing-plugin-git-out"
removeDir(gitTarget)
discard checked(wing & "template apply fromgit " & quoteShell(gitTarget) &
    " --name git_demo")
doAssert readFile(gitTarget / "file.txt").contains("git_demo from git")

# --- uninstall takes it out of the record and the registry ---------------------
discard checked(wing & "template uninstall fromgit")
let afterRemove = checked(wing & "template installed")
doAssert not afterRemove.contains("fromgit"), afterRemove
let registry = checked(wing & "template list --raw")
doAssert not registry.contains("fromgit\t"),
    "an uninstalled template should not be left in the registry: " & registry
