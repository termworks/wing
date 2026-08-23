## Flavour resolution and placeholder rendering for bundled templates.
##
## Every question here used to be answered by comparing a template's name to "python". A flavour is
## data now, so a template that declares flavours has them and one that does not, does not.

import std/[sequtils, strutils]

import ../types
import ../util

proc builtinLanguageTitle*(tmpl: TemplateSpec): string =
  if tmpl.language.len == 0:
    return ""
  tmpl.language[0].toUpperAscii() & tmpl.language.substr(1)

proc builtinTemplateFlavours*(tmpl: TemplateSpec): seq[string] =
  tmpl.flavours.mapIt(it.name)

proc builtinFlavourSummary*(tmpl: TemplateSpec): string =
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

proc normalizeBuiltinFlavour*(tmpl: TemplateSpec; requested: string): string =
  let flavours = builtinTemplateFlavours(tmpl)
  if flavours.len == 0:
    if requested.len > 0:
      die("Template '" & tmpl.name & "' does not support flavours", 2)
    return ""

  result = if requested.len > 0: requested.toLowerAscii() else: tmpl.defaultFlavour
  if not flavours.contains(result):
    die("Unknown flavour '" & requested & "' for template '" & tmpl.name &
        "'. Available flavours: " & flavours.join(", "), 2)

proc findFlavour(tmpl: TemplateSpec; flavour: string): int =
  ## An empty flavour means the default, which is what a template with no request gets.
  result = -1
  let wanted = if flavour.len > 0: flavour else: tmpl.defaultFlavour
  if wanted.len == 0:
    return
  for i, entry in tmpl.flavours:
    if entry.name == wanted:
      return i

proc builtinFlavourNixPackages*(tmpl: TemplateSpec; flavour: string): string =
  let idx = findFlavour(tmpl, flavour)
  if idx >= 0 and tmpl.flavours[idx].nixPackages.len > 0:
    return tmpl.flavours[idx].nixPackages
  tmpl.nixPackages

proc builtinEnvironmentDescription*(tmpl: TemplateSpec;
    flavour: string): string =
  let idx = findFlavour(tmpl, flavour)
  if idx >= 0 and tmpl.flavours[idx].environment.len > 0:
    return tmpl.flavours[idx].environment
  tmpl.environment

proc renderBuiltinTemplate*(content: string; tmpl: TemplateSpec;
    flavour = ""): string =
  content
    .replace("{{builtin_language}}", tmpl.language)
    .replace("{{builtin_language_title}}", builtinLanguageTitle(tmpl))
    .replace("{{builtin_nix_packages}}", builtinFlavourNixPackages(tmpl,
        flavour))
    .replace("{{builtin_flavour}}", flavour)
    .replace("{{builtin_environment_description}}",
        builtinEnvironmentDescription(tmpl, flavour))

proc builtinTemplateTags*(tmpl: TemplateSpec): seq[string] =
  tmpl.tags
