import std/[os, osproc]

const Binary* = "/tmp/wing-nim-test-wing"

proc run*(command: string): tuple[output: string, code: int] =
  let output = execCmdEx(command)
  (output.output, output.exitCode)

proc checked*(command: string): string =
  let res = run(command)
  doAssert res.code == 0, command & "\n" & res.output
  res.output

proc bobabrewPathFlag(): string =
  let nimbleDir = getEnv("NIMBLE_DIR", getHomeDir() / ".nimble")
  let candidates = @[
    nimbleDir / "pkgcache" / "githubcom_bresillabobabrew" / "src",
    nimbleDir / "pkgcache" / "githubcom_bresillabobabrew_0.1.0" / "src",
    getCurrentDir() / ".." / "bobabrew" / "src"
  ]
  for candidate in candidates:
    if dirExists(candidate):
      return " --path:" & quoteShell(candidate)
  ""

proc compileBinary*() =
  discard checked("nim c" & bobabrewPathFlag() & " --out:" &
      quoteShell(Binary) & " src/wing.nim")

proc freshEnv*(name: string): string =
  let dataHome = "/tmp/wing-" & name & "-data"
  let home = "/tmp/wing-" & name & "-home"
  removeDir(dataHome)
  removeDir(home)
  createDir(dataHome)
  createDir(home)
  "XDG_DATA_HOME=" & quoteShell(dataHome) & " HOME=" & quoteShell(home) & " "

proc wing*(envPrefix: string): string =
  envPrefix & quoteShell(Binary) & " "

proc resetDir*(path: string) =
  removeDir(path)
  createDir(path)
