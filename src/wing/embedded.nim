## Writes the compiled-in template sources into the data directory.

import std/os

import ./embedded_templates
import ./storage

proc embeddedTemplatesRoot*(): string =
  dataRoot() / "templates"

proc writeEmbeddedTemplateSources*(root: string; force: bool): tuple[
    written: int; skipped: int] =
  for item in EmbeddedTemplateFiles:
    let destination = root / item.group / item.path
    if fileExists(destination) and not force:
      inc result.skipped
    else:
      atomicWriteFile(destination, item.content)
      inc result.written

proc ensureEmbeddedTemplateSources*(force = false): tuple[root: string;
    written: int; skipped: int] =
  result.root = embeddedTemplatesRoot()
  let counts = writeEmbeddedTemplateSources(result.root, force)
  result.written = counts.written
  result.skipped = counts.skipped
