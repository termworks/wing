import std/strutils

# The version is read from wing.nimble at compile time rather than repeated here: the release
# tooling bumps the nimble file, and a copy in Nim source silently drifts a release behind.
const
  Version* = block:
    var found = ""
    for line in staticRead("../../wing.nimble").splitLines():
      let parts = line.split('=', 1)
      if parts.len == 2 and parts[0].strip() == "version":
        found = parts[1].strip().strip(chars = {'"'})
        break
    doAssert found.len > 0, "wing.nimble is missing its version line"
    found

  About* = "ultimate tool for managing development workflows"
