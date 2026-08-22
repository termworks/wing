import std/[os, strutils]

import test_support

compileBinary()

let envPrefix = freshEnv("templates")
let dp = dp(envPrefix)

let templateRoot = "/tmp/devpilot-templates-template"
let targetRoot = "/tmp/devpilot-templates-target"
resetDir(templateRoot)
removeDir(targetRoot)

writeFile(templateRoot / "README.md", "hello {{PROJECT_NAME}} {{project-name}}")
writeFile(templateRoot / "snake.txt", "{{snake_name}} {{NAME}}")

discard checked(dp & "template add base --description sample --path " &
    quoteShell(templateRoot) & " --language go")

let inferredTarget = "/tmp/devpilot-smart-project"
removeDir(inferredTarget)
discard checked(dp & "template apply base " & quoteShell(inferredTarget))
doAssert dirExists(inferredTarget)
doAssert readFile(inferredTarget / "README.md") ==
    "hello devpilot-smart-project devpilot-smart-project"

let existingTarget = "/tmp/devpilot-existing-template-target"
resetDir(existingTarget)
let existingWithoutName = run(dp & "template apply base " & quoteShell(
    existingTarget))
doAssert existingWithoutName.code != 0
doAssert existingWithoutName.output.contains("already exists")
doAssert existingWithoutName.output.contains("--name PROJECT_NAME")
doAssert not fileExists(existingTarget / "README.md")
discard checked(dp & "template apply base " & quoteShell(existingTarget) &
    " --name existing_project")
doAssert readFile(existingTarget / "README.md") ==
    "hello existing_project existing-project"

let dotTarget = "/tmp/devpilot-dot-template-target"
resetDir(dotTarget)
let dotWithoutName = run("cd " & quoteShell(dotTarget) & " && " & dp &
    "template apply base .")
doAssert dotWithoutName.code != 0
doAssert dotWithoutName.output.contains("Target path '.' already exists")
doAssert dotWithoutName.output.contains("--name PROJECT_NAME")
discard checked("cd " & quoteShell(dotTarget) & " && " & dp &
    "template apply base . --name dot_project")
doAssert readFile(dotTarget / "README.md") == "hello dot_project dot-project"

let dryRunTarget = "/tmp/devpilot-templates-dry-run"
removeDir(dryRunTarget)
let dryRun = checked(dp & "template apply base " & quoteShell(dryRunTarget) &
    " --name sample_app --dry-run")
doAssert dryRun.contains("Copy files:")
doAssert dryRun.contains("README.md")
doAssert not dirExists(dryRunTarget)

discard checked(dp & "template apply base " & quoteShell(targetRoot) &
    " --name sample_app")
doAssert readFile(targetRoot / "README.md") == "hello sample_app sample-app"
doAssert readFile(targetRoot / "snake.txt") == "sample_app SAMPLE_APP"

let conflict = run(dp & "template apply base " & quoteShell(targetRoot) &
    " --name sample_app")
doAssert conflict.code != 0
doAssert conflict.output.contains("Conflicts:")

writeFile(targetRoot / "README.md", "old")
discard checked(dp & "template apply base " & quoteShell(targetRoot) &
    " --name sample_app --skip-existing")
doAssert readFile(targetRoot / "README.md") == "old"

discard checked(dp & "template apply base " & quoteShell(targetRoot) &
    " --name sample_app --force")
doAssert readFile(targetRoot / "README.md") == "hello sample_app sample-app"

writeFile(templateRoot / "binary.bin", "abc\0{{PROJECT_NAME}}")
let binaryOutput = checked(dp & "template apply base " & quoteShell(
    targetRoot) & " --name sample_app --force")
doAssert binaryOutput.contains("Skipped placeholder replacements:")
doAssert readFile(targetRoot / "binary.bin") == "abc\0{{PROJECT_NAME}}"

discard checked(dp & "template set base --description updated --language nim " &
    "--framework cli --path " & quoteShell(templateRoot))
let updatedTemplate = checked(dp & "template info base")
doAssert updatedTemplate.contains("Description: updated")
doAssert updatedTemplate.contains("Language: nim")
doAssert updatedTemplate.contains("Framework: cli")

discard checked(dp & "template tag add base tui")
discard checked(dp & "template tag add base tui")
let taggedTemplate = checked(dp & "template info base")
doAssert taggedTemplate.contains("Tags: tui")
discard checked(dp & "template tag remove base tui")
let untaggedTemplate = checked(dp & "template info base")
doAssert untaggedTemplate.contains("Tags: None")

let builtins = checked(dp & "template builtins --raw")
doAssert builtins.contains("go\tgo\t")
doAssert builtins.contains("zig\tzig\t")
doAssert builtins.contains("nim\tnim\t")
doAssert builtins.contains("rust\trust\t")
doAssert builtins.contains("cpp\tcpp\t")
doAssert builtins.contains("python\tpython\t")
let builtinDisplay = checked(dp & "template builtins list")
doAssert builtinDisplay.contains("nix (default), uv, pixi, micromamba")
discard checked(dp & "template builtins install")
let builtinRegistry = checked(dp & "template list --raw")
doAssert builtinRegistry.contains("go\tgo\t")
doAssert builtinRegistry.contains("zig\tzig\t")
doAssert builtinRegistry.contains("nim\tnim\t")
doAssert builtinRegistry.contains("rust\trust\t")
doAssert builtinRegistry.contains("cpp\tcpp\t")
doAssert builtinRegistry.contains("python\tpython\t")
let pythonInfo = checked(dp & "template info python")
doAssert pythonInfo.contains("Flavours: nix (default), uv, pixi, micromamba")
let templateHelp = checked(dp & "template")
doAssert templateHelp.contains("--flavour FLAVOUR")

let builtinTarget = "/tmp/devpilot-templates-builtin-nim"
removeDir(builtinTarget)
discard checked(dp & "template apply nim " & quoteShell(builtinTarget) &
    " --name sample_app")
doAssert fileExists(builtinTarget / "sample_app.nimble")
doAssert fileExists(builtinTarget / "src" / "sample_app.nim")
doAssert readFile(builtinTarget / "sample_app.nimble").contains(
    "bin           = @[\"sample-app\"]")
doAssert readFile(builtinTarget / "src" / "sample_app.nim").contains(
    "sample_app")
doAssert readFile(builtinTarget / "README.md").contains("Small Nim starter")
doAssert readFile(builtinTarget / "flake.nix").contains("pkgs.nim")

let rustTarget = "/tmp/devpilot-templates-builtin-rust"
removeDir(rustTarget)
discard checked(dp & "template apply rust " & quoteShell(rustTarget) &
    " --name sample_app")
doAssert fileExists(rustTarget / "Cargo.toml")
doAssert fileExists(rustTarget / "src" / "lib.rs")
doAssert fileExists(rustTarget / "examples" / "main.rs")
doAssert readFile(rustTarget / "Cargo.toml").contains("name = \"sample-app\"")
doAssert readFile(rustTarget / "examples" / "main.rs").contains(
    "sample_app::name()")
doAssert readFile(rustTarget / "flake.nix").contains("pkgs.cargo")

let cppTarget = "/tmp/devpilot-templates-builtin-cpp"
removeDir(cppTarget)
discard checked(dp & "template apply cpp " & quoteShell(cppTarget) &
    " --name sample_app")
doAssert fileExists(cppTarget / "CMakeLists.txt")
doAssert fileExists(cppTarget / "include" / "sample_app" / "sample_app.hpp")
doAssert fileExists(cppTarget / "src" / "sample_app" / "sample_app.cpp")
doAssert fileExists(cppTarget / "test" / "basic_test.cpp")
doAssert readFile(cppTarget / "CMakeLists.txt").contains(
    "src/sample_app/sample_app.cpp")
doAssert readFile(cppTarget / "flake.nix").contains("pkgs.cmake")

let pythonTarget = "/tmp/devpilot-templates-builtin-python"
removeDir(pythonTarget)
let pythonOutput = checked(dp & "template apply python " & quoteShell(
    pythonTarget) & " --name sample_app")
doAssert pythonOutput.contains("flavour: nix")
doAssert fileExists(pythonTarget / "pyproject.toml")
doAssert fileExists(pythonTarget / "src" / "sample_app" / "__init__.py")
doAssert fileExists(pythonTarget / "src" / "sample_app" / "__main__.py")
doAssert fileExists(pythonTarget / "tests" / "test_cli.py")
doAssert fileExists(pythonTarget / "Makefile")
doAssert not dirExists(pythonTarget / ".venv")
doAssert not fileExists(pythonTarget / "pixi.toml")
doAssert not fileExists(pythonTarget / "environment.yml")
doAssert readFile(pythonTarget / "flake.nix").contains(
    "pkgs.python3.withPackages")
doAssert not readFile(pythonTarget / "flake.nix").contains("pkgs.uv")
doAssert readFile(pythonTarget / "Makefile").contains(
    "pure Nix (no virtualenv)")
doAssert readFile(pythonTarget / "README.md").contains(
    "No virtual environment is created")

let pythonUvTarget = "/tmp/devpilot-templates-builtin-python-uv"
removeDir(pythonUvTarget)
discard checked(dp & "template apply python " & quoteShell(pythonUvTarget) &
    " --name sample_app --flavour uv")
doAssert readFile(pythonUvTarget / "flake.nix").contains("pkgs.uv")
doAssert readFile(pythonUvTarget / "flake.nix").contains("pkgs.python3")
doAssert readFile(pythonUvTarget / "Makefile").contains("$(UV) sync")
doAssert readFile(pythonUvTarget / "Makefile").contains(
    "UV_PYTHON_DOWNLOADS := never")
doAssert readFile(pythonUvTarget / "README.md").contains("local `.venv`")

let pythonPixiTarget = "/tmp/devpilot-templates-builtin-python-pixi"
removeDir(pythonPixiTarget)
discard checked(dp & "template apply python " & quoteShell(pythonPixiTarget) &
    " --name sample_app --flavour=pixi")
doAssert readFile(pythonPixiTarget / "flake.nix").contains("pkgs.pixi")
doAssert fileExists(pythonPixiTarget / "pixi.toml")
doAssert readFile(pythonPixiTarget / "Makefile").contains("$(PIXI) install")

let pythonMicromambaTarget =
  "/tmp/devpilot-templates-builtin-python-micromamba"
removeDir(pythonMicromambaTarget)
discard checked(dp & "template apply python " & quoteShell(
    pythonMicromambaTarget) & " --name sample_app --flavor micromamba")
doAssert readFile(pythonMicromambaTarget / "flake.nix").contains(
    "pkgs.micromamba")
doAssert fileExists(pythonMicromambaTarget / "environment.yml")
doAssert readFile(pythonMicromambaTarget / "Makefile").contains(
    "$(MICROMAMBA) create")

let unknownFlavour = run(dp & "template apply python /tmp/devpilot-python-bad " &
    "--flavour conda")
doAssert unknownFlavour.code != 0
doAssert unknownFlavour.output.contains("Unknown flavour 'conda'")
let unsupportedFlavour = run(dp & "template apply nim /tmp/devpilot-nim-uv " &
    "--flavour uv")
doAssert unsupportedFlavour.code != 0
doAssert unsupportedFlavour.output.contains("does not support flavours")

let initDataHome = "/tmp/devpilot-init-data"
let initHome = "/tmp/devpilot-init-home"
removeDir(initDataHome)
removeDir(initHome)
createDir(initDataHome)
createDir(initHome)
let initPrefix = "XDG_DATA_HOME=" & quoteShell(initDataHome) & " HOME=" &
    quoteShell(initHome) & " "
let initOutput = checked(initPrefix & quoteShell(Binary) & " init")
doAssert initOutput.contains("Initialized devpilot data")
doAssert fileExists(initDataHome / "devpilot" / "templates" / "common" /
    "flake.nix")
doAssert fileExists(initDataHome / "devpilot" / "templates" / "nim" /
    "{{snake_name}}.nimble")
doAssert fileExists(initDataHome / "devpilot" / "templates" / "rust" /
    "Cargo.toml")
doAssert fileExists(initDataHome / "devpilot" / "templates" / "cpp" /
    "CMakeLists.txt")
doAssert fileExists(initDataHome / "devpilot" / "templates" / "python" /
    "base" / "pyproject.toml")
doAssert fileExists(initDataHome / "devpilot" / "templates" / "python" /
    "flavours" / "uv" / "Makefile")
doAssert fileExists(initDataHome / "devpilot" / "templates" / "python" /
    "flavours" / "pixi" / "pixi.toml")
doAssert fileExists(initDataHome / "devpilot" / "templates" / "python" /
    "flavours" / "micromamba" / "environment.yml")
let initializedTemplates = checked(initPrefix & quoteShell(Binary) &
    " template list --raw")
doAssert initializedTemplates.contains("go\tgo\t")
doAssert initializedTemplates.contains("zig\tzig\t")
doAssert initializedTemplates.contains("nim\tnim\t")
doAssert initializedTemplates.contains("rust\trust\t")
doAssert initializedTemplates.contains("cpp\tcpp\t")
doAssert initializedTemplates.contains("python\tpython\t")

discard checked(dp & "template rename base renamed")
let renamedTemplate = checked(dp & "template info renamed")
doAssert renamedTemplate.contains("Template: renamed")
discard checked(dp & "template add other --description other --path " &
    quoteShell(templateRoot))
let duplicateRename = run(dp & "template rename renamed other")
doAssert duplicateRename.code != 0
doAssert duplicateRename.output.contains("already exists")
let badTemplatePath = run(dp & "template set renamed --path /tmp/devpilot-missing-template")
doAssert badTemplatePath.code != 0
doAssert badTemplatePath.output.contains("does not exist")

let linkTemplate = "/tmp/devpilot-templates-link-template"
let linkTarget = "/tmp/devpilot-templates-link-target"
let outside = "/tmp/devpilot-templates-outside.txt"
resetDir(linkTemplate)
removeDir(linkTarget)
writeFile(outside, "outside")
createSymlink(outside, linkTemplate / "outside-link")
discard checked(dp & "template add links --description links --path " &
    quoteShell(linkTemplate))

let blockedLink = run(dp & "template apply links " & quoteShell(linkTarget))
doAssert blockedLink.code != 0
doAssert blockedLink.output.contains("Template contains symlinks")

discard checked(dp & "template apply links " & quoteShell(linkTarget) &
    " --allow-symlinks")
doAssert expandSymlink(linkTarget / "outside-link") == outside

discard checked(dp & "template remove renamed")
discard checked(dp & "template remove other")
discard checked(dp & "template remove links")

let missing = run(dp & "template info renamed")
doAssert missing.code != 0
