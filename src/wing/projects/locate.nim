## Finding a project when it might not be on this machine.
##
## The registry used to answer "what projects are there", which is only useful while every path in
## it is a path you can `cd` to. Once a project can live on another machine, every question about
## one has two halves -- which machine, and where on it -- and this is the half that answers the
## first.
##
## A project is addressed as `name` or as `machine:name`. The qualified form is not decoration: two
## machines can each have a `deploy`, and on a laptop that talks to five servers they will.

import std/[strutils]

import ../types

type
  Located* = object
    project*: Project
    qualified*: string ## how to name this one unambiguously

proc isRemote*(project: Project): bool =
  project.machine.len > 0

proc machineLabel*(project: Project): string =
  ## Which machine this project is on, for a listing and for qualifying a name. "local" rather than
  ## an empty cell: a blank column reads as missing data, and "local" is a machine you do not have
  ## to ssh to rather than a different kind of thing.
  if project.machine.len > 0: project.machine else: "local"

proc qualifiedName*(project: Project): string =
  ## Always machine-qualified, this one included. `local:api` has to be typable, or the answer to
  ## "which one did you mean" lists the name that was just rejected as ambiguous.
  machineLabel(project) & ":" & project.name

proc splitQualified*(reference: string): tuple[machine, name: string] =
  ## `lab:api` -> ("lab", "api"); `api` -> ("", "api").
  ##
  ## A Windows-style drive letter is not a concern here and a path is never passed to this, so the
  ## first colon is the separator with no further guessing.
  let colon = reference.find(':')
  if colon <= 0:
    return ("", reference)
  (reference[0 ..< colon], reference[colon + 1 .. ^1])

proc locate*(projects: seq[Project]; reference: string): seq[Located] =
  ## Every project the reference could mean. More than one is not an error here -- the caller
  ## decides whether to ask, because "which of these did you mean" is a better answer than picking
  ## one and being wrong on a machine you did not look at.
  let (machine, name) = splitQualified(reference)
  for project in projects:
    if project.name != name:
      continue
    # `local:` names this machine, which is stored as no machine at all -- so the name a listing
    # shows is a name that can be typed back in.
    if machine.len > 0 and machine != machineLabel(project):
      continue
    result.add(Located(project: project, qualified: qualifiedName(project)))

proc describeAmbiguity*(matches: seq[Located]): string =
  var names: seq[string]
  for match in matches:
    names.add(match.qualified)
  "'" & matches[0].project.name & "' is on " & $matches.len &
      " machines: " & names.join(", ") & " — name one of those instead"

proc byMachine*(projects: seq[Project]): seq[tuple[machine: string;
    items: seq[Project]]] =
  ## Grouped for display, local first and the rest in the order they were registered. Sorting by
  ## name would put a remote machine above the one you are sitting at, which is never what you
  ## wanted to read first.
  var order: seq[string]
  for project in projects:
    let name = machineLabel(project)
    if name notin order:
      order.add(name)
  if "local" in order:
    order.delete(order.find("local"))
    order.insert("local", 0)
  for name in order:
    var items: seq[Project]
    for project in projects:
      if machineLabel(project) == name:
        items.add(project)
    result.add((machine: name, items: items))
