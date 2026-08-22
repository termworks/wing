import std/[os, strutils]

import test_support

compileBinary()

# A template tree that exists only on disk: nothing here is compiled into the binary.
let tplRoot = "/tmp/wing-lua-templates"
let cfgHome = "/tmp/wing-lua-config"
let outRoot = "/tmp/wing-lua-out"
resetDir(tplRoot)
resetDir(cfgHome)
removeDir(outRoot)
createDir(tplRoot / "common")
createDir(tplRoot / "mine")
createDir(cfgHome / "wing")

writeFile(tplRoot / "mine" / "template.lua", """
local wing = require("wing")
wing.template("mine", {
  description = "declared on disk",
  language = "text",
  framework = "cli",
  tags = { "local", "text" },
})
""")
writeFile(tplRoot / "mine" / "README.md",
    "hello {{project_name}} built {{stamp}} by {{author}}")

let envPrefix = freshEnv("lua") & "XDG_CONFIG_HOME=" & quoteShell(cfgHome) &
    " WING_TEMPLATE_DIR=" & quoteShell(tplRoot) & " "
let wing = wing(envPrefix)

# --- a template declared in Lua is found, with no user config yet ---------------
let declared = checked(wing & "template builtins list --raw")
doAssert declared.contains("mine\ttext\t"), declared
doAssert not declared.contains("python\t"),
    "only the on-disk tree should be visible: " & declared

let describedByManifest = checked(wing & "template builtins list")
doAssert describedByManifest.contains("declared on disk"), describedByManifest

# --- the user config is loaded after the manifests, so the same name replaces ---
writeFile(cfgHome / "wing" / "init.lua", """
local wing = require("wing")

wing.template("mine", {
  description = "replaced by the user config",
  language = "text",
  tags = { "mine" },
})

wing.placeholders["{{author}}"] = "someone"
wing.placeholders["{{stamp}}"] = function(ctx)
  return ctx.template .. "/" .. ctx.name .. "/" .. ctx.flavour
end

wing.on.apply(function(ctx) print("HOOK1 " .. ctx.template) end)
wing.on.apply(function(ctx) error("this handler is broken") end)
wing.on.apply(function(ctx) print("HOOK3 " .. ctx.path) end)
""")

let overridden = checked(wing & "template builtins list")
doAssert overridden.contains("replaced by the user config"), overridden
doAssert not overridden.contains("declared on disk"),
    "re-registering a name should replace it, not add a second: " & overridden

# --- apply: placeholders resolve and every handler runs ------------------------
discard checked(wing & "init")
let applied = checked(wing & "template apply mine " & quoteShell(outRoot) &
    " --name demo_thing")

doAssert applied.contains("HOOK1 mine"), applied
doAssert applied.contains("HOOK3 " & outRoot), applied
# One that raises is reported and the rest still run, and the message names the file it came from.
doAssert applied.contains("this handler is broken"), applied
doAssert applied.contains("init.lua"), applied
doAssert applied.find("HOOK1") < applied.find("HOOK3"), "handlers run in registration order"

let rendered = readFile(outRoot / "README.md")
doAssert rendered.contains("hello demo_thing"), rendered
doAssert rendered.contains("by someone"),
    "a string placeholder should resolve: " & rendered
doAssert rendered.contains("built mine/demo_thing/"),
    "a computed placeholder should see the context: " & rendered

# The manifest describes the template; it must not land in what the template produces.
doAssert not fileExists(outRoot / "template.lua")

# --- a broken manifest names its own file rather than disappearing quietly -----
let brokenRoot = "/tmp/wing-lua-broken"
resetDir(brokenRoot)
createDir(brokenRoot / "oops")
writeFile(brokenRoot / "oops" / "template.lua", "this is not lua at all(")
let brokenPrefix = freshEnv("luabroken") & "WING_TEMPLATE_DIR=" &
    quoteShell(brokenRoot) & " "
let broken = run(brokenPrefix & quoteShell(Binary) & " template builtins list")
doAssert broken.code != 0, broken.output
doAssert broken.output.contains("template.lua"), broken.output
