## `wing init` — seeds the data directory and registers whatever templates it can find.

import std/os

import ../builtins/install
import ../builtins/paths
import ../builtins/registry
import ../cliargs
import ../storage
import ../store/machines
import ../store/projects
import ../store/templates
import ../util

proc handleInit*(argsIn: seq[string]) =
  var args = argsIn
  let force = popFlag(args, ["--force"])
  rejectUnknownOptions(args)
  if args.len > 0:
    die("Usage: wing init [--force]", 2)

  discard ensureProjectsFile()
  discard ensureMachinesFile()
  let templatesPath = ensureTemplatesFile()
  echo "Initialized wing data: " & dataRoot()

  # Templates are not carried inside the binary any more, so init reports where it looked rather
  # than writing a copy out. Nothing else here depends on them being present.
  let root = builtinTemplatesRoot()
  if root.len == 0:
    echo "No templates found. Put a template tree at " & dataRoot() /
        "templates" &
        ", or point WING_TEMPLATE_DIR at one."
    return

  var templates = parseTemplates(templatesPath)
  installBuiltinTemplates(templatesPath, templates, force, root)
  echo "Templates: " & root & " (" & $builtinSpecs().len & " declared)"
