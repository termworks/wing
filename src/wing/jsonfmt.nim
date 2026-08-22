## JSON rendering for the domain records exposed by --json flags.

import std/strutils

import ./types

proc jsonString*(value: string): string =
  "\"" & value
    .replace("\\", "\\\\")
    .replace("\"", "\\\"")
    .replace("\n", "\\n") & "\""

proc jsonStringArray*(values: seq[string]): string =
  result = "["
  for i, value in values:
    if i > 0:
      result.add(", ")
    result.add(jsonString(value))
  result.add("]")

proc projectJson*(project: Project): string =
  "{\"name\": " & jsonString(project.name) & ", \"path\": " &
      jsonString(project.path) & ", \"namespace\": " &
      jsonString(project.namespace) & ", \"template\": " &
      jsonString(project.templateName) & ", \"description\": " &
      jsonString(project.description) & ", \"language\": " &
      jsonString(project.language) & ", \"framework\": " &
      jsonString(project.framework) & ", \"tags\": " & jsonStringArray(
          project.tags) &
      ", \"created_at\": " & jsonString(project.createdAt) &
          ", \"updated_at\": " &
      jsonString(project.updatedAt) & "}"

proc hostJson*(host: Host): string =
  "{\"ip\": " & jsonString(host.ip) & ", \"port\": " & jsonString(host.port) &
      ", \"iface\": " & jsonString(host.iface) & "}"

proc machineJson*(machine: Machine): string =
  var hosts = "["
  for i, host in machine.hosts:
    if i > 0:
      hosts.add(", ")
    hosts.add(hostJson(host))
  hosts.add("]")
  "{\"name\": " & jsonString(machine.name) & ", \"username\": " &
      jsonString(machine.username) & ", \"key\": " & jsonString(machine.key) &
      ", \"proxy_jump\": " & jsonString(machine.proxyJump) &
      ", \"forward_agent\": " & (if machine.forwardAgent: "true" else: "false") &
      ", \"hosts\": " & hosts & "}"

proc templateJson*(tmpl: Template): string =
  "{\"name\": " & jsonString(tmpl.name) & ", \"description\": " &
      jsonString(tmpl.description) & ", \"path\": " & jsonString(tmpl.path) &
      ", \"language\": " & jsonString(tmpl.language) & ", \"framework\": " &
      jsonString(tmpl.framework) & ", \"tags\": " & jsonStringArray(tmpl.tags) &
      ", \"created_at\": " & jsonString(tmpl.createdAt) & ", \"updated_at\": " &
      jsonString(tmpl.updatedAt) & "}"

proc printJsonArray*[T](items: seq[T]; render: proc(item: T): string) =
  echo "["
  for i, item in items:
    let suffix = if i == items.high: "" else: ","
    echo "  " & render(item) & suffix
  echo "]"
