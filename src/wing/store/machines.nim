## machines.toml parsing and serialization.

import std/[os, strutils]

import ../storage
import ../toml
import ../types

proc parseMachines*(path: string): seq[Machine] =
  let content = readConfig(path)
  var currentMachine = -1
  var currentHost = -1
  for rawLine in content.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith("#"):
      continue
    if line == "[[machines]]":
      result.add(Machine(name: "", username: "", key: "", proxyJump: "",
          forwardAgent: false, tags: @[], hosts: @[]))
      currentMachine = result.high
      currentHost = -1
    elif line == "[[machines.hosts]]":
      if currentMachine >= 0:
        result[currentMachine].hosts.add(Host(ip: "", port: "22",
            iface: "local"))
        currentHost = result[currentMachine].hosts.high
    elif line.contains("=") and currentMachine >= 0:
      let (key, value) = splitKeyValue(line)
      if currentHost >= 0 and key in ["ip", "port", "iface"]:
        case key
        of "ip": result[currentMachine].hosts[currentHost].ip = unquoteToml(value)
        of "port": result[currentMachine].hosts[currentHost].port = unquoteToml(value)
        of "iface": result[currentMachine].hosts[
            currentHost].iface = unquoteToml(value)
        else: discard
      else:
        case key
        of "name": result[currentMachine].name = unquoteToml(value)
        of "username": result[currentMachine].username = unquoteToml(value)
        of "key": result[currentMachine].key = unquoteToml(value)
        of "proxy_jump", "proxyJump":
          result[currentMachine].proxyJump = unquoteToml(value)
        of "forward_agent", "forwardAgent":
          result[currentMachine].forwardAgent = value.strip() == "true"
        of "tags": result[currentMachine].tags = parseStringArray(value)
        else: discard

proc writeMachines*(path: string; machines: seq[Machine]) =
  var text = schemaHeader()
  if machines.len == 0:
    text.add("machines = []\n")
  else:
    for machine in machines:
      text.add("[[machines]]\n")
      text.add("name = " & tomlString(machine.name) & "\n")
      text.add("username = " & tomlString(machine.username) & "\n")
      if machine.key.len > 0:
        text.add("key = " & tomlString(machine.key) & "\n")
      if machine.proxyJump.len > 0:
        text.add("proxy_jump = " & tomlString(machine.proxyJump) & "\n")
      if machine.forwardAgent:
        text.add("forward_agent = true\n")
      if machine.tags.len > 0:
        text.add("tags = " & tomlArray(machine.tags) & "\n")
      for host in machine.hosts:
        text.add("\n[[machines.hosts]]\n")
        text.add("ip = " & tomlString(host.ip) & "\n")
        text.add("port = " & tomlString(host.port) & "\n")
        text.add("iface = " & tomlString(host.iface) & "\n")
      text.add("\n")
  atomicWriteFile(path, text)

proc defaultMachine*(): Machine =
  let hostName = getEnv("HOSTNAME", "localhost")
  let userName = getEnv("USER", "root")
  Machine(
    name: hostName,
    username: userName,
    key: "",
    hosts: @[Host(ip: "127.0.0.1", port: "22", iface: "local")]
  )

proc ensureMachinesFile*(): string =
  result = configPath("machines.toml")
  if (not fileExists(result)) or getFileSize(result) == 0:
    writeMachines(result, @[defaultMachine()])
