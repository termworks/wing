## `wing init` — seeds the data directory and bundled templates.

import ../builtins/install
import ../cliargs
import ../embedded
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
  let seeded = ensureEmbeddedTemplateSources(force)

  var templates = parseTemplates(templatesPath)
  installBuiltinTemplates(templatesPath, templates, force, seeded.root)

  echo "Initialized wing data: " & dataRoot()
  echo "Embedded template sources: " & seeded.root & " (" & $seeded.written &
      " written, " & $seeded.skipped & " skipped)"
