import std/[os, osproc, strutils, times]

import test_support

compileBinary()

let envPrefix = freshEnv("templates")
let wing = wing(envPrefix)

let templateRoot = "/tmp/wing-templates-template"
let targetRoot = "/tmp/wing-templates-target"
resetDir(templateRoot)
removeDir(targetRoot)

writeFile(templateRoot / "README.md", "hello {{PROJECT_NAME}} {{project-name}}")
writeFile(templateRoot / "snake.txt", "{{snake_name}} {{NAME}}")

discard checked(wing & "template add base --description sample --path " &
    quoteShell(templateRoot) & " --language go")

let inferredTarget = "/tmp/wing-smart-project"
removeDir(inferredTarget)
discard checked(wing & "template apply base " & quoteShell(inferredTarget))
doAssert dirExists(inferredTarget)
doAssert readFile(inferredTarget / "README.md") ==
    "hello wing-smart-project wing-smart-project"

let existingTarget = "/tmp/wing-existing-template-target"
resetDir(existingTarget)
let existingWithoutName = run(wing & "template apply base " & quoteShell(
    existingTarget))
doAssert existingWithoutName.code != 0
doAssert existingWithoutName.output.contains("already exists")
doAssert existingWithoutName.output.contains("--name PROJECT_NAME")
doAssert not fileExists(existingTarget / "README.md")
discard checked(wing & "template apply base " & quoteShell(existingTarget) &
    " --name existing_project")
doAssert readFile(existingTarget / "README.md") ==
    "hello existing_project existing-project"

let dotTarget = "/tmp/wing-dot-template-target"
resetDir(dotTarget)
let dotWithoutName = run("cd " & quoteShell(dotTarget) & " && " & wing &
    "template apply base .")
doAssert dotWithoutName.code != 0
doAssert dotWithoutName.output.contains("Target path '.' already exists")
doAssert dotWithoutName.output.contains("--name PROJECT_NAME")
discard checked("cd " & quoteShell(dotTarget) & " && " & wing &
    "template apply base . --name dot_project")
doAssert readFile(dotTarget / "README.md") == "hello dot_project dot-project"

let dryRunTarget = "/tmp/wing-templates-dry-run"
removeDir(dryRunTarget)
let dryRun = checked(wing & "template apply base " & quoteShell(dryRunTarget) &
    " --name sample_app --dry-run")
doAssert dryRun.contains("Copy files:")
doAssert dryRun.contains("README.md")
doAssert not dirExists(dryRunTarget)

discard checked(wing & "template apply base " & quoteShell(targetRoot) &
    " --name sample_app")
doAssert readFile(targetRoot / "README.md") == "hello sample_app sample-app"
doAssert readFile(targetRoot / "snake.txt") == "sample_app SAMPLE_APP"

let conflict = run(wing & "template apply base " & quoteShell(targetRoot) &
    " --name sample_app")
doAssert conflict.code != 0
doAssert conflict.output.contains("Conflicts:")

writeFile(targetRoot / "README.md", "old")
discard checked(wing & "template apply base " & quoteShell(targetRoot) &
    " --name sample_app --skip-existing")
doAssert readFile(targetRoot / "README.md") == "old"

discard checked(wing & "template apply base " & quoteShell(targetRoot) &
    " --name sample_app --force")
doAssert readFile(targetRoot / "README.md") == "hello sample_app sample-app"

writeFile(templateRoot / "binary.bin", "abc\0{{PROJECT_NAME}}")
let binaryOutput = checked(wing & "template apply base " & quoteShell(
    targetRoot) & " --name sample_app --force")
doAssert binaryOutput.contains("Skipped placeholder replacements:")
doAssert readFile(targetRoot / "binary.bin") == "abc\0{{PROJECT_NAME}}"

discard checked(wing & "template set base --description updated --language nim " &
    "--framework cli --path " & quoteShell(templateRoot))
let updatedTemplate = checked(wing & "template info base")
doAssert updatedTemplate.contains("Description: updated")
doAssert updatedTemplate.contains("Language: nim")
doAssert updatedTemplate.contains("Framework: cli")

discard checked(wing & "template tag add base tui")
discard checked(wing & "template tag add base tui")
let taggedTemplate = checked(wing & "template info base")
doAssert taggedTemplate.contains("Tags: tui")
discard checked(wing & "template tag remove base tui")
let untaggedTemplate = checked(wing & "template info base")
doAssert untaggedTemplate.contains("Tags: None")

let builtins = checked(wing & "template builtins --raw")
doAssert builtins.contains("go\tgo\t")
doAssert builtins.contains("zig\tzig\t")
doAssert builtins.contains("nim\tnim\t")
doAssert builtins.contains("rust\trust\t")
doAssert builtins.contains("cpp\tcpp\t")
doAssert builtins.contains("c\tc\t")
doAssert builtins.contains("v\tv\t")
doAssert builtins.contains("haskell\thaskell\t")
doAssert builtins.contains("odin\todin\t")
doAssert builtins.contains("crystal\tcrystal\t")
doAssert builtins.contains("c3\tc3\t")
doAssert builtins.contains("ocaml\tocaml\t")
doAssert builtins.contains("vala\tvala\t")
doAssert builtins.contains("d\td\t")
doAssert builtins.contains("python\tpython\t")
doAssert builtins.contains("carbon\tcarbon\t")
doAssert builtins.contains("mojo\tmojo\t")
let builtinDisplay = checked(wing & "template builtins list")
doAssert builtinDisplay.contains("nix (default), uv, pixi, micromamba")
discard checked(wing & "template builtins install")
let builtinRegistry = checked(wing & "template list --raw")
doAssert builtinRegistry.contains("go\tgo\t")
doAssert builtinRegistry.contains("zig\tzig\t")
doAssert builtinRegistry.contains("nim\tnim\t")
doAssert builtinRegistry.contains("rust\trust\t")
doAssert builtinRegistry.contains("cpp\tcpp\t")
doAssert builtinRegistry.contains("python\tpython\t")
let pythonInfo = checked(wing & "template info python")
doAssert pythonInfo.contains("Flavours: nix (default), uv, pixi, micromamba")
let templateHelp = checked(wing & "template")
doAssert templateHelp.contains("--flavour FLAVOUR")

let builtinTarget = "/tmp/wing-templates-builtin-nim"
removeDir(builtinTarget)
discard checked(wing & "template apply nim " & quoteShell(builtinTarget) &
    " --name sample_app")
doAssert fileExists(builtinTarget / "sample_app.nimble")
doAssert fileExists(builtinTarget / "src" / "sample_app.nim")
doAssert readFile(builtinTarget / "sample_app.nimble").contains(
    "bin           = @[\"sample-app\"]")
doAssert readFile(builtinTarget / "src" / "sample_app.nim").contains(
    "sample_app")
doAssert readFile(builtinTarget / "README.md").contains("Small Nim starter")
doAssert readFile(builtinTarget / "flake.nix").contains("pkgs.nim")

let rustTarget = "/tmp/wing-templates-builtin-rust"
removeDir(rustTarget)
discard checked(wing & "template apply rust " & quoteShell(rustTarget) &
    " --name sample_app")
doAssert fileExists(rustTarget / "Cargo.toml")
doAssert fileExists(rustTarget / "src" / "lib.rs")
doAssert fileExists(rustTarget / "examples" / "main.rs")
doAssert readFile(rustTarget / "Cargo.toml").contains("name = \"sample-app\"")
doAssert readFile(rustTarget / "examples" / "main.rs").contains(
    "sample_app::name()")
doAssert readFile(rustTarget / "flake.nix").contains("pkgs.cargo")

# C++ defaults to the xmake flavour: the sources come from base/, the build file from the flavour.
let cppTarget = "/tmp/wing-templates-builtin-cpp"
removeDir(cppTarget)
discard checked(wing & "template apply cpp " & quoteShell(cppTarget) &
    " --name sample_app")
doAssert fileExists(cppTarget / "xmake.lua")
doAssert not fileExists(cppTarget / "CMakeLists.txt")
doAssert fileExists(cppTarget / "include" / "sample_app" / "sample_app.hpp")
doAssert fileExists(cppTarget / "src" / "sample_app" / "sample_app.cpp")
doAssert fileExists(cppTarget / "test" / "basic_test.cpp")
doAssert readFile(cppTarget / "flake.nix").contains("pkgs.xmake")
# .make.lua drives the build system; it is not the build system.
doAssert readFile(cppTarget / ".make.lua").contains("sh.xmake(")
# musl and static are the default build. The compiler differs by language and it is not taste:
# musl-clang carries no C++ standard library, so C defaults to clang and C++ defaults to gcc.
doAssert readFile(cppTarget / ".make.lua").contains(
    "DEFAULT_TOOLCHAIN = \"gcc\""),
    "C++ should default to gcc, the only musl toolchain with a C++ standard library"
doAssert readFile(cppTarget / ".make.lua").contains("MUSL_CC")
doAssert readFile(cppTarget / "flake.nix").contains("MUSL_CC = pkgs.pkgsMusl.stdenv.cc")
doAssert readFile(cppTarget / "flake.nix").contains("MUSL_CLANG = pkgs.musl.dev")

# The cmake flavour swaps the build file and the dev shell, and nothing else.
let cppCmakeTarget = "/tmp/wing-templates-builtin-cpp-cmake"
removeDir(cppCmakeTarget)
discard checked(wing & "template apply cpp " & quoteShell(cppCmakeTarget) &
    " --name sample_app --flavour cmake")
doAssert fileExists(cppCmakeTarget / "CMakeLists.txt")
doAssert not fileExists(cppCmakeTarget / "xmake.lua")
doAssert fileExists(cppCmakeTarget / "src" / "sample_app" / "sample_app.cpp")
doAssert readFile(cppCmakeTarget / "CMakeLists.txt").contains(
    "src/sample_app/sample_app.cpp")
doAssert readFile(cppCmakeTarget / "flake.nix").contains("pkgs.cmake")
doAssert readFile(cppCmakeTarget / ".make.lua").contains("sh.cmake(")

# C is the same pair of build systems over C sources.
let cTarget = "/tmp/wing-templates-builtin-c"
removeDir(cTarget)
discard checked(wing & "template apply c " & quoteShell(cTarget) &
    " --name sample_app")
doAssert fileExists(cTarget / "xmake.lua")
doAssert readFile(cTarget / "xmake.lua").contains("set_languages(\"c17\")")
doAssert fileExists(cTarget / "include" / "sample_app" / "sample_app.h")
doAssert fileExists(cTarget / "src" / "sample_app.c")
doAssert fileExists(cTarget / "test" / "basic_test.c")
doAssert readFile(cTarget / "flake.nix").contains("pkgs.xmake")
doAssert readFile(cTarget / ".make.lua").contains(
    "DEFAULT_TOOLCHAIN = \"clang\""),
    "C should default to clang, which musl-clang supports"

let cCmakeTarget = "/tmp/wing-templates-builtin-c-cmake"
removeDir(cCmakeTarget)
discard checked(wing & "template apply c " & quoteShell(cCmakeTarget) &
    " --name sample_app --flavour cmake")
doAssert fileExists(cCmakeTarget / "CMakeLists.txt")
doAssert readFile(cCmakeTarget / "flake.nix").contains("pkgs.cmake")

# V is its own compiler and build system, so it has no flavour to choose.
let vTarget = "/tmp/wing-templates-builtin-v"
removeDir(vTarget)
discard checked(wing & "template apply v " & quoteShell(vTarget) &
    " --name sample_app")
doAssert fileExists(vTarget / "v.mod")
doAssert fileExists(vTarget / "src" / "main.v")
doAssert fileExists(vTarget / "src" / "main_test.v")
doAssert readFile(vTarget / "v.mod").contains("name: 'sample_app'")
doAssert readFile(vTarget / "flake.nix").contains("pkgs.vlang")
doAssert readFile(vTarget / ".make.lua").contains("sh.v(")

# D builds with dub; the compiler is a choice rather than a flavour.
let dTarget = "/tmp/wing-templates-builtin-d"
removeDir(dTarget)
discard checked(wing & "template apply d " & quoteShell(dTarget) &
    " --name sample_app")
doAssert fileExists(dTarget / "dub.json")
doAssert fileExists(dTarget / "source" / "app.d")
doAssert fileExists(dTarget / "source" / "sample_app" / "core.d")
doAssert readFile(dTarget / "dub.json").contains("\"name\": \"sample_app\"")
doAssert readFile(dTarget / "flake.nix").contains("pkgs.dub")
doAssert readFile(dTarget / ".make.lua").contains("sh.dub(")
doAssert readFile(dTarget / ".make.lua").contains("ldc2, dmd or gdc")

# Zig is a build system as well as a language, but only for Zig: it is not a C or C++ flavour.
let cppZig = run(wing & "template apply cpp /tmp/wing-cpp-zig --name x --flavour zig")
doAssert cppZig.code != 0
doAssert cppZig.output.contains("Unknown flavour"), cppZig.output

let pythonTarget = "/tmp/wing-templates-builtin-python"
removeDir(pythonTarget)
let pythonOutput = checked(wing & "template apply python " & quoteShell(
    pythonTarget) & " --name sample_app")
doAssert pythonOutput.contains("flavour: nix")
doAssert fileExists(pythonTarget / "pyproject.toml")
doAssert fileExists(pythonTarget / "src" / "sample_app" / "__init__.py")
doAssert fileExists(pythonTarget / "src" / "sample_app" / "__main__.py")
doAssert fileExists(pythonTarget / "tests" / "test_cli.py")
doAssert fileExists(pythonTarget / ".make.lua")
doAssert fileExists(pythonTarget / ".env.lua")
doAssert not dirExists(pythonTarget / ".venv")
doAssert not fileExists(pythonTarget / "pixi.toml")
doAssert not fileExists(pythonTarget / "environment.yml")
doAssert readFile(pythonTarget / "flake.nix").contains(
    "pkgs.python3.withPackages")
doAssert not readFile(pythonTarget / "flake.nix").contains("pkgs.uv")
doAssert readFile(pythonTarget / ".make.lua").contains(
    "There is no virtual environment")
doAssert readFile(pythonTarget / "README.md").contains(
    "No virtual environment is created")

let pythonUvTarget = "/tmp/wing-templates-builtin-python-uv"
removeDir(pythonUvTarget)
discard checked(wing & "template apply python " & quoteShell(pythonUvTarget) &
    " --name sample_app --flavour uv")
doAssert readFile(pythonUvTarget / "flake.nix").contains("pkgs.uv")
doAssert readFile(pythonUvTarget / "flake.nix").contains("pkgs.python3")
doAssert readFile(pythonUvTarget / ".make.lua").contains("sh.uv(\"sync\")")
doAssert readFile(pythonUvTarget / ".make.lua").contains(
    "uv owns the local .venv")
doAssert readFile(pythonUvTarget / "README.md").contains("local `.venv`")

let pythonPixiTarget = "/tmp/wing-templates-builtin-python-pixi"
removeDir(pythonPixiTarget)
discard checked(wing & "template apply python " & quoteShell(pythonPixiTarget) &
    " --name sample_app --flavour=pixi")
doAssert readFile(pythonPixiTarget / "flake.nix").contains("pkgs.pixi")
doAssert fileExists(pythonPixiTarget / "pixi.toml")
doAssert readFile(pythonPixiTarget / ".make.lua").contains("sh.pixi(\"install\")")

let pythonMicromambaTarget =
  "/tmp/wing-templates-builtin-python-micromamba"
removeDir(pythonMicromambaTarget)
discard checked(wing & "template apply python " & quoteShell(
    pythonMicromambaTarget) & " --name sample_app --flavor micromamba")
doAssert readFile(pythonMicromambaTarget / "flake.nix").contains(
    "pkgs.micromamba")
doAssert fileExists(pythonMicromambaTarget / "environment.yml")
doAssert readFile(pythonMicromambaTarget / ".make.lua").contains(
    "sh.micromamba(\"env\", \"update\"")

let unknownFlavour = run(wing & "template apply python /tmp/wing-python-bad " &
    "--flavour conda")
doAssert unknownFlavour.code != 0
doAssert unknownFlavour.output.contains("Unknown flavour 'conda'")
let unsupportedFlavour = run(wing & "template apply nim /tmp/wing-nim-uv " &
    "--flavour uv")
doAssert unsupportedFlavour.code != 0
doAssert unsupportedFlavour.output.contains("does not support flavours")

let initDataHome = "/tmp/wing-init-data"
let initHome = "/tmp/wing-init-home"
removeDir(initDataHome)
removeDir(initHome)
createDir(initDataHome)
createDir(initHome)
let initPrefix = "XDG_DATA_HOME=" & quoteShell(initDataHome) & " HOME=" &
    quoteShell(initHome) & " "
# Templates are not carried inside the binary any more, so init registers whatever tree it can
# reach rather than writing one out. Here that is the repository's own templates/, via the cwd.
let initOutput = checked(initPrefix & quoteShell(Binary) & " init")
doAssert initOutput.contains("Initialized wing data")
doAssert initOutput.contains("Declared: 17"), initOutput

# A reachable tree that declares nothing is reported, not treated as a failure.
let emptyRoot = "/tmp/wing-init-empty-templates"
resetDir(emptyRoot)
let bareInit = checked("WING_TEMPLATE_DIR=" & quoteShell(emptyRoot) & " " &
    initPrefix & quoteShell(Binary) & " init")
doAssert bareInit.contains("Declared: 0"), bareInit
let initializedTemplates = checked(initPrefix & quoteShell(Binary) &
    " template list --raw")
doAssert initializedTemplates.contains("go\tgo\t")
doAssert initializedTemplates.contains("zig\tzig\t")
doAssert initializedTemplates.contains("nim\tnim\t")
doAssert initializedTemplates.contains("rust\trust\t")
doAssert initializedTemplates.contains("cpp\tcpp\t")
doAssert initializedTemplates.contains("python\tpython\t")

discard checked(wing & "template rename base renamed")
let renamedTemplate = checked(wing & "template info renamed")
doAssert renamedTemplate.contains("Template: renamed")
discard checked(wing & "template add other --description other --path " &
    quoteShell(templateRoot))
let duplicateRename = run(wing & "template rename renamed other")
doAssert duplicateRename.code != 0
doAssert duplicateRename.output.contains("already exists")
let badTemplatePath = run(wing & "template set renamed --path /tmp/wing-missing-template")
doAssert badTemplatePath.code != 0
doAssert badTemplatePath.output.contains("does not exist")

let linkTemplate = "/tmp/wing-templates-link-template"
let linkTarget = "/tmp/wing-templates-link-target"
let outside = "/tmp/wing-templates-outside.txt"
resetDir(linkTemplate)
removeDir(linkTarget)
writeFile(outside, "outside")
createSymlink(outside, linkTemplate / "outside-link")
discard checked(wing & "template add links --description links --path " &
    quoteShell(linkTemplate))

let blockedLink = run(wing & "template apply links " & quoteShell(linkTarget))
doAssert blockedLink.code != 0
doAssert blockedLink.output.contains("Template contains symlinks")

discard checked(wing & "template apply links " & quoteShell(linkTarget) &
    " --allow-symlinks")
doAssert expandSymlink(linkTarget / "outside-link") == outside

discard checked(wing & "template remove renamed")
discard checked(wing & "template remove other")
discard checked(wing & "template remove links")

let missing = run(wing & "template info renamed")
doAssert missing.code != 0

# --- every bundled template carries logic of its own --------------------------
# Not decoration: each one generates a flake.nix and a .env.lua that call nix, so a machine without
# nix produces a project whose dev shell cannot come up. The template is what knows that.
for name in ["c", "c3", "carbon", "cpp", "crystal", "d", "go", "haskell", "mojo",
             "nim", "ocaml", "odin", "python", "rust", "v", "vala", "zig"]:
  let logic = "templates" / name / "init.lua"
  doAssert fileExists(logic), name & " should carry an init.lua: " & logic
  doAssert readFile(logic).contains("wing.on.check"),
      name & "'s init.lua should register a check"

# Applying on a machine without nix says so, and names what is missing.
let noNixTarget = "/tmp/wing-templates-no-nix"
removeDir(noNixTarget)
let withoutNix = run("PATH=/usr/bin:/bin " & envPrefix & quoteShell(Binary) &
    " template apply go " & quoteShell(noNixTarget) & " --name sample_app")
doAssert withoutNix.code == 0, withoutNix.output
doAssert withoutNix.output.contains("nix is not installed"), withoutNix.output
# The flake is still written: .env.lua calls nix_develop(), so a project without it would have a
# broken directory environment rather than a working one missing a file.
doAssert fileExists(noNixTarget / "flake.nix"),
    "the flake belongs to the set even when nix is absent"
doAssert not fileExists(noNixTarget / "init.lua")

# --- Haskell needs a PascalCase module name, which the raw project name is not ---
let hsTarget = "/tmp/wing-templates-builtin-haskell"
removeDir(hsTarget)
discard checked(wing & "template apply haskell " & quoteShell(hsTarget) &
    " --name sample_app")
doAssert fileExists(hsTarget / "src" / "SampleApp.hs"),
    "{{PascalName}} should render a module name Haskell will accept"
doAssert readFile(hsTarget / "src" / "SampleApp.hs").contains("module SampleApp")
doAssert readFile(hsTarget / "sample-app.cabal").contains("exposed-modules:  SampleApp")
doAssert readFile(hsTarget / "flake.nix").contains("pkgs.ghc")

let odinTarget = "/tmp/wing-templates-builtin-odin"
removeDir(odinTarget)
discard checked(wing & "template apply odin " & quoteShell(odinTarget) &
    " --name sample_app")
doAssert fileExists(odinTarget / "src" / "main.odin")
doAssert fileExists(odinTarget / "src" / "main_test.odin")
doAssert readFile(odinTarget / "flake.nix").contains("pkgs.odin")
# odinfmt ships with ols, not odin, so the dev shell has to bring both.
doAssert readFile(odinTarget / "flake.nix").contains("pkgs.ols")

# Crystal compiles to a native binary, so it belongs here with the rest.
let crTarget = "/tmp/wing-templates-builtin-crystal"
removeDir(crTarget)
discard checked(wing & "template apply crystal " & quoteShell(crTarget) &
    " --name sample_app")
doAssert fileExists(crTarget / "shard.yml")
doAssert fileExists(crTarget / "src" / "sample_app.cr")
doAssert fileExists(crTarget / "spec" / "sample_app_spec.cr")
doAssert readFile(crTarget / "src" / "sample_app.cr").contains("module SampleApp")
doAssert readFile(crTarget / "flake.nix").contains("pkgs.crystal")

let c3Target = "/tmp/wing-templates-builtin-c3"
removeDir(c3Target)
discard checked(wing & "template apply c3 " & quoteShell(c3Target) &
    " --name sample_app")
doAssert fileExists(c3Target / "project.json")
doAssert fileExists(c3Target / "src" / "main.c3")
doAssert fileExists(c3Target / "test" / "sample_app_test.c3")
# project.json names lib/ as a dependency search path, and c3c refuses to build without it.
doAssert dirExists(c3Target / "lib"),
    "c3c will not build when its dependency search path is missing"
doAssert readFile(c3Target / "flake.nix").contains("pkgs.c3c")

# OCaml derives a module name by upper-casing only the first letter of the filename, so the
# PascalCase placeholder is the wrong shape here and {{Snake_name}} is the right one.
let mlTarget = "/tmp/wing-templates-builtin-ocaml"
removeDir(mlTarget)
discard checked(wing & "template apply ocaml " & quoteShell(mlTarget) &
    " --name sample_app")
doAssert fileExists(mlTarget / "lib" / "sample_app.ml")
doAssert readFile(mlTarget / "bin" / "main.ml").contains("Sample_app."),
    "an OCaml module reference should be Sample_app, not SampleApp"
doAssert readFile(mlTarget / "flake.nix").contains("pkgs.ocaml")

# Vala compiles through C, so the dev shell needs a C compiler as well as valac.
let valaTarget = "/tmp/wing-templates-builtin-vala"
removeDir(valaTarget)
discard checked(wing & "template apply vala " & quoteShell(valaTarget) &
    " --name sample_app")
doAssert fileExists(valaTarget / "meson.build")
doAssert fileExists(valaTarget / "src" / "sample_app.vala")
doAssert readFile(valaTarget / "src" / "sample_app.vala").contains("namespace SampleApp")
doAssert readFile(valaTarget / "flake.nix").contains("pkgs.vala")
doAssert readFile(valaTarget / "flake.nix").contains("pkgs.gcc"),
    "vala emits C, so a C compiler belongs in the dev shell"

# --- Carbon and Mojo bring their own toolchain, because no distribution has one ---
# Both compilers are published as prebuilt archives and neither is in nixpkgs, so the template
# declares the derivation that unpacks one. That is the whole reason `nix_packages` is free-form
# Nix text rather than a list of package names.
let carbonTarget = "/tmp/wing-templates-builtin-carbon"
removeDir(carbonTarget)
discard checked(wing & "template apply carbon " & quoteShell(carbonTarget) &
    " --name sample_app")
doAssert fileExists(carbonTarget / "src" / "main.carbon")
doAssert fileExists(carbonTarget / "src" / "lib.carbon")
doAssert fileExists(carbonTarget / "src" / "lib_test.carbon")
# A Carbon package name is a single identifier, so the module placeholder has to render one.
doAssert readFile(carbonTarget / "src" / "lib.carbon").contains(
    "package SampleApp"),
    "{{PascalName}} should render a package name Carbon will accept"
let carbonFlake = readFile(carbonTarget / "flake.nix")
doAssert carbonFlake.contains("carbon_toolchain-"), carbonFlake
doAssert carbonFlake.contains("nightly"), "the Carbon toolchain is pinned to a nightly"
# The pin is what `make toolchain` moves, so both lines it rewrites have to be there to find.
doAssert carbonFlake.contains("hash = \"sha256-"), carbonFlake

let mojoTarget = "/tmp/wing-templates-builtin-mojo"
removeDir(mojoTarget)
discard checked(wing & "template apply mojo " & quoteShell(mojoTarget) &
    " --name sample_app")
doAssert fileExists(mojoTarget / "src" / "main.mojo")
doAssert fileExists(mojoTarget / "src" / "main_test.mojo")
doAssert fileExists(mojoTarget / "src" / "demo.mojo")
let mojoFlake = readFile(mojoTarget / "flake.nix")
doAssert mojoFlake.contains("conda.modular.com"), mojoFlake
# mojo resolves its formatter through its own bin directory, so the shell has to supply mblack too.
doAssert mojoFlake.contains("mblack"), mojoFlake
doAssert mojoFlake.contains("MODULAR_HOME"),
    "the compiler needs a writable MODULAR_HOME, which the store path is not"

# --- a generated project keeps its version where its language already keeps it ---
# There is no version file of wing's own: `veri`, the bumper behind `make release`, reads each
# language's own manifest, and a file invented here would be one more copy for nothing to update.
for name in ["c", "c3", "carbon", "cpp", "crystal", "d", "go", "haskell", "mojo",
             "nim", "ocaml", "odin", "python", "rust", "v", "vala", "zig"]:
  doAssert not fileExists("templates" / name / "PROJECT"),
      name & " should not carry a PROJECT file"
doAssert not fileExists("templates" / "common" / "PROJECT"),
    "the shared base should not carry a PROJECT file either"

for recipes in walkDirRec("templates"):
  if recipes.extractFilename != ".make.lua":
    continue
  let text = readFile(recipes)
  doAssert not text.contains("oslo.fs.read(\"PROJECT\")"),
      recipes & " still reads a PROJECT file"
  # Either a manifest is read, or the version comes from the tag `make release` creates.
  doAssert text.contains("oslo.fs.read(") or text.contains(
      "git\", \"describe\""), recipes & " should read a version from somewhere"

# The version each template reports is the one its own manifest carries.
let verTarget = "/tmp/wing-templates-version"
removeDir(verTarget)
discard checked(wing & "template apply rust " & quoteShell(verTarget) & " --name sample_app")
doAssert readFile(verTarget / "Cargo.toml").contains("version = \"0.1.0\"")
doAssert not fileExists(verTarget / "PROJECT"),
    "a generated project should have no PROJECT file"

# --- a generated project arrives under version control ------------------------
# The recipes assume it: `make release` runs git-rel, which works on `develop` and nowhere else, so
# a project that is only loose files is one `git flow init` short of its own release recipe.
let repoTarget = "/tmp/wing-templates-repo"
removeDir(repoTarget)
let repoOut = checked(wing & "template apply rust " & quoteShell(repoTarget) &
    " --name sample_app")
doAssert dirExists(repoTarget / ".git"), repoOut
if repoOut.contains("were not created"):
  # No git-flow, or no author identity to commit with: the repository is still created, and the
  # line says which of the two it was rather than leaving a half-made project unexplained.
  doAssert repoOut.contains("Initialized a git repository"), repoOut
else:
  doAssert repoOut.contains("git-flow (main, develop)"), repoOut
  let branch = execCmdEx("git -C " & quoteShell(repoTarget) &
      " rev-parse --abbrev-ref HEAD").output.strip()
  doAssert branch == "develop", "a new project should start on develop, not " & branch

# Tracked, not merely written. A flake only sees files git knows about, so in a repository where
# nothing is tracked `nix develop` fails on flake.nix -- and every generated project brings up its
# dev shell from .env.lua. This is why the repository is not left empty.
doAssert execCmdEx("git -C " & quoteShell(repoTarget) &
    " ls-files flake.nix").output.strip() == "flake.nix",
    "flake.nix has to be tracked or the dev shell cannot come up"

# --no-git leaves it alone, for generating into something that is not a project of its own.
let bareTarget = "/tmp/wing-templates-repo-none"
removeDir(bareTarget)
discard checked(wing & "template apply rust " & quoteShell(bareTarget) &
    " --name sample_app --no-git")
doAssert not dirExists(bareTarget / ".git"), "--no-git should not create a repository"

# Generating inside a checkout does not nest a second repository in it.
let outerRepo = "/tmp/wing-templates-repo-outer"
resetDir(outerRepo)
doAssert execCmdEx("git init -q " & quoteShell(outerRepo)).exitCode == 0
let innerOut = checked(wing & "template apply rust " & quoteShell(outerRepo /
    "pkg") & " --name sample_app")
doAssert not dirExists(outerRepo / "pkg" / ".git"), innerOut
doAssert innerOut.contains("already under version control"), innerOut

# --- every generated project carries the licence it says it is under ----------
# Several manifests already declare MIT -- Cargo.toml, dub.json, pyproject.toml, the nimble file --
# and a declaration with no LICENSE beside it is a claim the repository cannot back up.
let licenceTarget = "/tmp/wing-templates-licence"
removeDir(licenceTarget)
discard checked(wing & "template apply rust " & quoteShell(licenceTarget) &
    " --name sample_app --no-git")
let licence = readFile(licenceTarget / "LICENSE")
doAssert licence.startsWith("MIT License"), licence
doAssert licence.contains("bresilla (trim.bresilla@bresilla.com)"), licence
# The copyright year is the year it was generated, not the year the template was written.
doAssert licence.contains("Copyright (c) " & $now().year), licence
doAssert not licence.contains("{{"), "the licence should have no placeholders left"
