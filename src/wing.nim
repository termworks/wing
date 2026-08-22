import std/os

import wing/app
import wing/tui/app as tui

when isMainModule:
  var args = commandLineParams()
  if args.len == 0 or args[0] in ["tui", "ui", "dashboard"]:
    if args.len > 0:
      args.delete(0)
    tui.runTui(args)
  else:
    app.main()
