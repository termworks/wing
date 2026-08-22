## Turns add-form field values into wing CLI command strings.

import std/[os, strutils]

import ./model

proc hasFlag*(args: seq[string]; names: openArray[string]): bool =
  for arg in args:
    for name in names:
      if arg == name:
        return true

proc valueAfter*(args: seq[string]; names: openArray[string]): string =
  for i, arg in args:
    for name in names:
      if arg == name and i + 1 < args.len:
        return args[i + 1]
      let prefix = name & "="
      if arg.startsWith(prefix):
        return arg[prefix.len .. ^1]

proc formError*(message: string): FormBuildResult =
  FormBuildResult(ok: false, error: message)

proc formCommand*(command: string): FormBuildResult =
  FormBuildResult(ok: true, command: command)

proc requireField*(value, label: string): string =
  if value.strip().len == 0:
    label & " is required"
  else:
    ""

proc tagArgs*(tags: string): string =
  for rawTag in tags.replace(",", " ").splitWhitespace():
    result.add(" --tags " & quoteShell(rawTag))

proc projectFormCommand*(name, path, namespace, language, framework,
    tags: string): FormBuildResult =
  let nameError = requireField(name, "project name")
  if nameError.len > 0:
    return formError(nameError)
  let pathError = requireField(path, "project path")
  if pathError.len > 0:
    return formError(pathError)
  var command = "project --namespace " & quoteShell(if namespace.strip().len ==
      0: "default" else: namespace.strip()) & " add " & quoteShell(
      name.strip()) & " --path " & quoteShell(path.strip())
  if language.strip().len > 0:
    command.add(" --language " & quoteShell(language.strip()))
  if framework.strip().len > 0:
    command.add(" --framework " & quoteShell(framework.strip()))
  command.add(tagArgs(tags))
  formCommand(command)

proc machineFormCommand*(name, username, keyPath,
    host: string): FormBuildResult =
  let nameError = requireField(name, "machine name")
  if nameError.len > 0:
    return formError(nameError)
  let hostError = requireField(host, "machine host")
  if hostError.len > 0:
    return formError(hostError)
  var command = "machine add " & quoteShell(name.strip()) & " " &
      quoteShell(host.strip())
  if username.strip().len > 0:
    command.add(" --username " & quoteShell(username.strip()))
  if keyPath.strip().len > 0:
    command.add(" --key " & quoteShell(keyPath.strip()))
  formCommand(command)

proc templateFormCommand*(name, description, path, language,
    framework: string): FormBuildResult =
  let nameError = requireField(name, "template name")
  if nameError.len > 0:
    return formError(nameError)
  let descriptionError = requireField(description, "template description")
  if descriptionError.len > 0:
    return formError(descriptionError)
  let pathError = requireField(path, "template path")
  if pathError.len > 0:
    return formError(pathError)
  if not (fileExists(path.strip()) or dirExists(path.strip())):
    return formError("template path does not exist")
  var command = "template add " & quoteShell(name.strip()) & " --description " &
      quoteShell(description.strip()) & " --path " & quoteShell(path.strip())
  if language.strip().len > 0:
    command.add(" --language " & quoteShell(language.strip()))
  if framework.strip().len > 0:
    command.add(" --framework " & quoteShell(framework.strip()))
  formCommand(command)
