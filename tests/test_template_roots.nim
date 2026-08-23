import std/[os, strutils]

import test_support

compileBinary()

# Two template roots at once. The data dir is searched before the config dir, so the config dir is
# where a user wins -- which is the whole point of having more than one.
let dataHome = "/tmp/wing-roots-data"
let home = "/tmp/wing-roots-home"
let cfgHome = "/tmp/wing-roots-config"
let outRoot = "/tmp/wing-roots-out"
for dir in [dataHome, home, cfgHome]:
  resetDir(dir)
removeDir(outRoot)

let dataTemplates = dataHome / "wing" / "templates"
let userTemplates = cfgHome / "wing" / "templates"
createDir(dataTemplates / "common")
createDir(dataTemplates / "shared")
createDir(dataTemplates / "both")
createDir(userTemplates / "common")
createDir(userTemplates / "both")
createDir(userTemplates / "mine")

proc manifest(dir, name, description: string) =
  writeFile(dir / "template.lua", """
local wing = require("wing")
wing.template(""" & "\"" & name & "\"" & """, {
  description = """ & "\"" & description & "\"" & """,
  language = "text",
})
""")

# The lower-priority root: a common/ with two files, and two templates.
writeFile(dataTemplates / "common" / "SHARED.md", "shared from the data root")
writeFile(dataTemplates / "common" / "OVERRIDE.md", "data root version")
manifest(dataTemplates / "shared", "shared", "only in the data root")
writeFile(dataTemplates / "shared" / "own.txt", "shared own file")
manifest(dataTemplates / "both", "both", "the data root version")
writeFile(dataTemplates / "both" / "own.txt", "data version of both")

# The higher-priority root: one overriding common file, and two templates.
writeFile(userTemplates / "common" / "OVERRIDE.md", "user version wins")
manifest(userTemplates / "both", "both", "the user version")
writeFile(userTemplates / "both" / "own.txt", "user version of both")
manifest(userTemplates / "mine", "mine", "only in the user root")
writeFile(userTemplates / "mine" / "own.txt", "mine own file")

let envPrefix = "XDG_DATA_HOME=" & quoteShell(dataHome) & " HOME=" &
    quoteShell(home) & " XDG_CONFIG_HOME=" & quoteShell(cfgHome) & " "
let wing = wing(envPrefix)

# --- both roots contribute, and the later one wins by name --------------------
let listed = checked(wing & "template builtins list --raw")
doAssert listed.contains("shared\t"), listed
doAssert listed.contains("mine\t"), listed
doAssert listed.contains("both\t"), listed

let described = checked(wing & "template builtins list")
doAssert described.contains("only in the data root"), described
doAssert described.contains("only in the user root"), described
doAssert described.contains("the user version"), described
doAssert not described.contains("the data root version"),
    "a name declared in two roots should resolve to the later one only: " & described

# `init` names every root it searched, so "which tree did that come from" is answerable.
let initOut = checked(wing & "init")
doAssert initOut.contains(dataTemplates), initOut
doAssert initOut.contains(userTemplates), initOut

# --- common/ layers across roots ----------------------------------------------
discard checked(wing & "template apply mine " & quoteShell(outRoot) &
    " --name demo")
doAssert readFile(outRoot / "own.txt").contains("mine own file")
# Untouched by the user root, so the data root's copy is used.
doAssert readFile(outRoot / "SHARED.md").contains("shared from the data root")
# Replaced by one file in the user root, without copying the rest of common/.
doAssert readFile(outRoot / "OVERRIDE.md").contains("user version wins"),
    "a later root's common/ file should win: " & readFile(outRoot / "OVERRIDE.md")

# --- an overridden template brings its own files, not the shadowed one's ------
let bothOut = "/tmp/wing-roots-both"
removeDir(bothOut)
discard checked(wing & "template apply both " & quoteShell(bothOut) & " --name demo")
doAssert readFile(bothOut / "own.txt").contains("user version of both"),
    "the winning declaration's files should be used"

# --- a template with no common/ anywhere still applies ------------------------
let loneRoot = "/tmp/wing-roots-lone"
let loneOut = "/tmp/wing-roots-lone-out"
resetDir(loneRoot)
removeDir(loneOut)
createDir(loneRoot / "solo")
manifest(loneRoot / "solo", "solo", "no common anywhere")
writeFile(loneRoot / "solo" / "only.txt", "just this")
let lonePrefix = freshEnv("roots-lone") & "WING_TEMPLATE_DIR=" &
    quoteShell(loneRoot) & " "
discard checked(lonePrefix & quoteShell(Binary) & " init")
discard checked(lonePrefix & quoteShell(Binary) & " template apply solo " &
    quoteShell(loneOut) & " --name demo")
doAssert readFile(loneOut / "only.txt").contains("just this")

# --- an absolute dir points outside every root --------------------------------
let elsewhere = "/tmp/wing-roots-elsewhere"
let elsewhereOut = "/tmp/wing-roots-elsewhere-out"
resetDir(elsewhere)
removeDir(elsewhereOut)
writeFile(elsewhere / "file.txt", "from outside the roots")
writeFile(cfgHome / "wing" / "init.lua",
    """
local wing = require("wing")
wing.template("outside", {
  description = "lives outside every root",
  language = "text",
  dir = """ & "\"" & elsewhere & "\"" & """,
})
""")
discard checked(wing & "init")
discard checked(wing & "template apply outside " & quoteShell(elsewhereOut) &
    " --name demo")
doAssert readFile(elsewhereOut / "file.txt").contains("from outside the roots"),
    "an absolute dir should be taken as written"
