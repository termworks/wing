import std/os

const
  Version = "0.5.3"
  About = "{{PROJECT_NAME}}"

proc showHelp() =
  echo About
  echo ""
  echo "Usage:"
  echo "  {{kebab_name}} [--help] [--version]"

proc main*() =
  let args = commandLineParams()
  if args.len == 0 or args[0] in ["-h", "--help"]:
    showHelp()
  elif args[0] in ["-V", "--version"]:
    echo Version
  else:
    stderr.writeLine("unknown command: " & args[0])
    quit(2)

when isMainModule:
  main()
