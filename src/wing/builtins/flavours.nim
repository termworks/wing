## Flavour resolution and placeholder rendering for bundled templates.

import std/strutils

import ../types
import ../util
import ./data

proc builtinLanguageTitle*(tmpl: BuiltinTemplate): string =
  if tmpl.language.len == 0:
    return ""
  tmpl.language[0].toUpperAscii() & tmpl.language.substr(1)

proc builtinTemplateFlavours*(tmpl: BuiltinTemplate): seq[string] =
  result = @[]
  for flavour in tmpl.flavours.split(","):
    let cleaned = flavour.strip().toLowerAscii()
    if cleaned.len > 0:
      result.add(cleaned)

proc builtinFlavourSummary*(tmpl: BuiltinTemplate): string =
  let flavours = builtinTemplateFlavours(tmpl)
  if flavours.len == 0:
    return "None"
  var labels: seq[string] = @[]
  for flavour in flavours:
    if flavour == tmpl.defaultFlavour:
      labels.add(flavour & " (default)")
    else:
      labels.add(flavour)
  labels.join(", ")

proc normalizeBuiltinFlavour*(tmpl: BuiltinTemplate;
    requested: string): string =
  let flavours = builtinTemplateFlavours(tmpl)
  if flavours.len == 0:
    if requested.len > 0:
      die("Template '" & tmpl.name & "' does not support flavours", 2)
    return ""

  result = if requested.len > 0: requested.toLowerAscii() else:
      tmpl.defaultFlavour
  if not flavours.contains(result):
    die("Unknown flavour '" & requested & "' for template '" & tmpl.name &
        "'. Available flavours: " & flavours.join(", "), 2)

proc builtinFlavourNixPackages*(tmpl: BuiltinTemplate;
    flavour: string): string =
  if tmpl.name != "python":
    return tmpl.nixPackages
  case flavour
  of "", "nix":
    PythonNixPackages
  of "uv":
    PythonUvNixPackages
  of "pixi":
    PythonPixiNixPackages
  of "micromamba":
    PythonMicromambaNixPackages
  else:
    tmpl.nixPackages

proc builtinEnvironmentDescription*(tmpl: BuiltinTemplate;
    flavour: string): string =
  if tmpl.name != "python":
    return ""
  case flavour
  of "", "nix":
    "Python and all development packages come directly from Nix. No virtual environment is created."
  of "uv":
    "Python and uv come from Nix. Run `make setup` to create and sync the local `.venv` managed by uv."
  of "pixi":
    "Pixi comes from Nix. Run `make setup` to create and sync the local `.pixi` environment."
  of "micromamba":
    "Micromamba comes from Nix. Run `make setup` to create and sync the local `.micromamba` environment."
  else:
    ""

proc renderBuiltinTemplate*(content: string; tmpl: BuiltinTemplate;
    flavour = ""): string =
  content
    .replace("{{builtin_language}}", tmpl.language)
    .replace("{{builtin_language_title}}", builtinLanguageTitle(tmpl))
    .replace("{{builtin_nix_packages}}", builtinFlavourNixPackages(tmpl,
        flavour))
    .replace("{{builtin_flavour}}", flavour)
    .replace("{{builtin_environment_description}}",
        builtinEnvironmentDescription(tmpl, flavour))

proc builtinTemplateTags*(tmpl: BuiltinTemplate): seq[string] =
  result = @[]
  for tag in tmpl.tags.split(","):
    let cleaned = tag.strip()
    if cleaned.len > 0:
      result.add(cleaned)
