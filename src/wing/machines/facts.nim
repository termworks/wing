## What a machine is: os, kernel, arch, cpus, memory, disk, uptime.
##
## Kept in the data directory rather than in `machines.toml`, because this is not configuration --
## nobody edits it, and losing it costs one round trip. `machines.toml` says what you told wing;
## this says what the machine answered.

import std/[os, strutils]

import ../jsonfmt
import ../storage
import ../toml
import ../util

type
  MachineFacts* = object
    machine*: string
    os*: string
    kernel*: string
    arch*: string
    cpus*: string
    memory*: string
    disk*: string
    uptime*: string
    collectedAt*: string

const factsProbe* = """
os=$(. /etc/os-release 2>/dev/null && printf '%s' "${PRETTY_NAME:-$NAME}" || uname -s)
printf 'os\t%s\n' "$os"
printf 'kernel\t%s\n' "$(uname -r)"
printf 'arch\t%s\n' "$(uname -m)"
printf 'cpus\t%s\n' "$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo '?')"
printf 'memory\t%s\n' "$(free -h 2>/dev/null | awk '/^Mem:/ {print $3 " / " $2}')"
printf 'disk\t%s\n' "$(df -h / 2>/dev/null | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')"
printf 'uptime\t%s\n' "$(uptime -p 2>/dev/null || uptime)"
"""
  ## One shell script, not seven commands: a machine reached seven times is seven round trips, and
  ## the whole point of collecting facts is to pay for one. Every line falls back rather than
  ## failing, so a busybox host answers with what it has instead of nothing at all.

proc factsFile*(): string =
  dataRoot() / "machine-facts.toml"

proc parseProbeOutput*(machine, output: string): MachineFacts =
  result = MachineFacts(machine: machine, collectedAt: nowStamp())
  for line in output.splitLines():
    let parts = line.split('\t', 1)
    if parts.len != 2:
      continue
    let value = parts[1].strip()
    case parts[0].strip()
    of "os": result.os = value
    of "kernel": result.kernel = value
    of "arch": result.arch = value
    of "cpus": result.cpus = value
    of "memory": result.memory = value
    of "disk": result.disk = value
    of "uptime": result.uptime = value
    else: discard

proc parseFacts*(path: string): seq[MachineFacts] =
  let content = readConfig(path)
  var current = -1
  for rawLine in content.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith("#"):
      continue
    if line == "[[facts]]":
      result.add(MachineFacts())
      current = result.high
    elif current >= 0 and line.contains("="):
      let (key, value) = splitKeyValue(line)
      case key
      of "machine": result[current].machine = unquoteToml(value)
      of "os": result[current].os = unquoteToml(value)
      of "kernel": result[current].kernel = unquoteToml(value)
      of "arch": result[current].arch = unquoteToml(value)
      of "cpus": result[current].cpus = unquoteToml(value)
      of "memory": result[current].memory = unquoteToml(value)
      of "disk": result[current].disk = unquoteToml(value)
      of "uptime": result[current].uptime = unquoteToml(value)
      of "collected_at": result[current].collectedAt = unquoteToml(value)
      else: discard

proc writeFacts*(path: string; entries: seq[MachineFacts]) =
  var text = schemaHeader()
  if entries.len == 0:
    text.add("facts = []\n")
  else:
    for entry in entries:
      text.add("[[facts]]\n")
      text.add("machine = " & tomlString(entry.machine) & "\n")
      text.add("os = " & tomlString(entry.os) & "\n")
      text.add("kernel = " & tomlString(entry.kernel) & "\n")
      text.add("arch = " & tomlString(entry.arch) & "\n")
      text.add("cpus = " & tomlString(entry.cpus) & "\n")
      text.add("memory = " & tomlString(entry.memory) & "\n")
      text.add("disk = " & tomlString(entry.disk) & "\n")
      text.add("uptime = " & tomlString(entry.uptime) & "\n")
      text.add("collected_at = " & tomlString(entry.collectedAt) & "\n\n")
  atomicWriteFile(path, text)

proc findFacts*(entries: seq[MachineFacts]; machine: string): int =
  result = -1
  for i, entry in entries:
    if entry.machine == machine:
      return i

proc factsJson*(entry: MachineFacts): string =
  "{\"machine\": " & jsonString(entry.machine) &
      ", \"os\": " & jsonString(entry.os) &
      ", \"kernel\": " & jsonString(entry.kernel) &
      ", \"arch\": " & jsonString(entry.arch) &
      ", \"cpus\": " & jsonString(entry.cpus) &
      ", \"memory\": " & jsonString(entry.memory) &
      ", \"disk\": " & jsonString(entry.disk) &
      ", \"uptime\": " & jsonString(entry.uptime) &
      ", \"collected_at\": " & jsonString(entry.collectedAt) & "}"

proc printFacts*(entries: seq[MachineFacts]; raw, asJson: bool) =
  if asJson:
    printJsonArray(entries, factsJson)
  elif raw:
    for e in entries:
      echo e.machine & "\t" & e.os & "\t" & e.kernel & "\t" & e.arch & "\t" &
          e.cpus & "\t" & e.memory & "\t" & e.disk & "\t" & e.uptime
  else:
    var rows: seq[seq[string]]
    for e in entries:
      rows.add(@[e.machine, unknownIfEmpty(e.os), unknownIfEmpty(e.arch),
                 unknownIfEmpty(e.cpus), unknownIfEmpty(e.memory),
                 unknownIfEmpty(e.disk), unknownIfEmpty(e.uptime)])
    echo table(@["Machine", "OS", "Arch", "CPUs", "Memory", "Disk", "Uptime"], rows)
