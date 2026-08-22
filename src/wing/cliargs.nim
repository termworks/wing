## Option and flag extraction from a mutable argument vector.

import std/strutils

import ./util

proc popFlag*(args: var seq[string]; names: openArray[string]): bool =
  var i = 0
  while i < args.len:
    for name in names:
      if args[i] == name:
        args.delete(i)
        return true
    inc i

proc popValue*(args: var seq[string]; names: openArray[string];
    defaultValue = ""): string =
  var i = 0
  while i < args.len:
    for name in names:
      if args[i] == name:
        if i + 1 >= args.len:
          die("Missing value for " & name, 2)
        result = args[i + 1]
        args.delete(i + 1)
        args.delete(i)
        return
      let prefix = name & "="
      if args[i].startsWith(prefix):
        result = args[i][prefix.len .. ^1]
        args.delete(i)
        return
    inc i
  defaultValue

proc popValues*(args: var seq[string]; names: openArray[string]): seq[string] =
  while true:
    let before = args.len
    let value = popValue(args, names, "")
    if args.len == before:
      break
    result.add(value)

proc requireArgs*(args: seq[string]; count: int; usage: string) =
  if args.len < count:
    die("Usage: " & usage, 2)

proc rejectUnknownOptions*(args: seq[string]) =
  for arg in args:
    if arg.startsWith("-"):
      die("Unknown option: " & arg, 2)
