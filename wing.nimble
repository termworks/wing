# Package

version       = "0.5.0"
author        = "Trim Bresilla"
description   = "Development workflow and project management CLI"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
bin           = @["wing"]

requires "nim >= 2.2.0"
requires "https://github.com/bresilla/bobabrew"

task test, "Run CLI regression tests":
  exec "sh -c 'nimble_dir=\"${NIMBLE_DIR:-$HOME/.nimble}\"; bobabrew_path=\"\"; for p in \"$nimble_dir/pkgcache/githubcom_bresillabobabrew/src\" \"$nimble_dir/pkgcache/githubcom_bresillabobabrew_0.1.0/src\" \"../bobabrew/src\"; do if [ -d \"$p\" ]; then bobabrew_path=\"--path:$p\"; break; fi; done; for t in tests/test_*.nim; do case \"$t\" in *test_support.nim) continue;; esac; nim c $bobabrew_path -r \"$t\" || exit 1; done'"
