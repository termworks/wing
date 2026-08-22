# Package

version       = "0.5.3"
author        = "Trim Bresilla"
description   = "Development workflow and project management CLI"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
bin           = @["wing"]

requires "nim >= 2.2.0"
requires "https://github.com/bresilla/bobabrew"

task test, "Run CLI regression tests":
  exec "sh -c 'for t in tests/test_*.nim; do case \"$t\" in *test_support.nim) continue;; esac; nim c -r \"$t\" || exit 1; done'"
