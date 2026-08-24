## The bobabrew program: key handling, update, view, and entry point.

import std/[os, strutils]

import boba

import ../dashboard
import ../types
import ./commands
import ./forms
import ./model
import ./render
import ./state

proc tuiHelp*() =
  echo """
Usage: wing tui [--snapshot] [--command COMMAND]

Options:
  --snapshot         Print a non-interactive dashboard summary
  --command COMMAND  Run a wing command through the TUI command runner
  -h, --help         Print help information

Keys:
  Left/Right, h/l, Tab, 1-4   Switch sections
  Up/Down, j/k                Move selection
  PageUp/PageDown             Move faster
  /                           Filter current view
  :                           Command palette; type any normal wing command
  a                           Open add form for the current section
  d                           Delete selected item after confirmation
  Enter                       Show selected item details
  r                           Reload data
  ?                           Show this help in the TUI
  q, Esc, Ctrl-C              Quit
"""

proc showOverlay*(m: WingApp; title, content: string) =
  m.mode = modeOverlay
  m.overlayTitle = title
  m.overlayLines = if content.len == 0: @[
      "No output."] else: content.splitLines()
  m.overlayScroll = 0

proc showPrompt*(m: WingApp; kind: PromptKind; title, initial: string;
    history: seq[string] = @[]) =
  m.mode = modePrompt
  m.promptKind = kind
  m.promptTitle = title
  m.promptValue = initial
  m.promptHistory = history
  m.promptHistoryIndex = history.len

proc runAndOverlay*(m: WingApp; command, titlePrefix: string) =
  let res = runCliCommand(command)
  m.data = loadDashboardData()
  m.state.message = if res.code == 0: "ok: " & command else: "failed: " & command
  m.showOverlay(titlePrefix & " (" & $res.code & ")", res.output)

proc startAddForm*(m: WingApp; section: DashboardSection) =
  m.formSectionTitle = section.title
  m.formName = ""
  m.formPath = ""
  m.formNamespace = ""
  m.formLanguage = ""
  m.formFramework = ""
  m.formTags = ""
  m.formDescription = ""
  m.formUsername = ""
  m.formKey = ""
  m.formHost = ""

  case section.title
  of "Projects":
    m.showPrompt(promptProjectName, section.title & " form · name", "")
  of "Machines":
    m.showPrompt(promptMachineName, section.title & " form · name", "")
  of "Templates":
    m.showPrompt(promptTemplateName, section.title & " form · name", "")
  of "Sync":
    m.showOverlay("Add sync target",
        "Use the CLI — sync targets need several fields:\n  wing sync add NAME --project P --machine M --remote PATH")
  else:
    m.showOverlay("Validation", "Unsupported form section: " & section.title)

proc finishForm*(m: WingApp; built: FormBuildResult) =
  if built.ok:
    m.runAndOverlay(built.command, "Add result")
  elif built.error.len > 0:
    m.state.message = built.error
    m.showOverlay("Validation", built.error)
  else:
    m.mode = modeDashboard

proc acceptPrompt*(m: WingApp; value: string) =
  let v = value.strip()
  case m.promptKind
  of promptFilter:
    m.state.filter = v
    m.state.cursor = 0
    m.state.scroll = 0
    m.mode = modeDashboard
  of promptCommand:
    let res = runCliCommand(v)
    if res.code == 0:
      m.state.commandHistory.add(v)
    m.data = loadDashboardData()
    m.state.message = if res.code == 0: "ok: " & v else: "failed: " & v
    m.showOverlay("Command result (" & $res.code & ")", res.output)
  of promptDeleteConfirm:
    if v == "yes":
      m.runAndOverlay(m.deleteCommandText, "Delete result")
    else:
      m.state.message = "delete cancelled"
      m.mode = modeDashboard
  of promptProjectName:
    m.formName = v
    m.showPrompt(promptProjectPath, m.formSectionTitle & " form · path",
        getCurrentDir())
  of promptProjectPath:
    m.formPath = v
    m.showPrompt(promptProjectNamespace, m.formSectionTitle &
        " form · namespace", "default")
  of promptProjectNamespace:
    m.formNamespace = v
    m.showPrompt(promptProjectLanguage, m.formSectionTitle &
        " form · language", "")
  of promptProjectLanguage:
    m.formLanguage = v
    m.showPrompt(promptProjectFramework, m.formSectionTitle &
        " form · framework", "")
  of promptProjectFramework:
    m.formFramework = v
    m.showPrompt(promptProjectTags, m.formSectionTitle &
        " form · tags comma-separated", "")
  of promptProjectTags:
    m.formTags = v
    m.finishForm(projectFormCommand(m.formName, m.formPath, m.formNamespace,
        m.formLanguage, m.formFramework, m.formTags))
  of promptMachineName:
    m.formName = v
    m.showPrompt(promptMachineUsername, m.formSectionTitle &
        " form · username", getEnv("USER", "user"))
  of promptMachineUsername:
    m.formUsername = v
    m.showPrompt(promptMachineKey, m.formSectionTitle & " form · key", "")
  of promptMachineKey:
    m.formKey = v
    m.showPrompt(promptMachineHost, m.formSectionTitle &
        " form · host IP[:PORT][:IFACE]", "127.0.0.1:22:local")
  of promptMachineHost:
    m.formHost = v
    m.finishForm(machineFormCommand(m.formName, m.formUsername, m.formKey,
        m.formHost))
  of promptTemplateName:
    m.formName = v
    m.showPrompt(promptTemplateDescription, m.formSectionTitle &
        " form · description", "")
  of promptTemplateDescription:
    m.formDescription = v
    m.showPrompt(promptTemplatePath, m.formSectionTitle & " form · path",
        getCurrentDir())
  of promptTemplatePath:
    m.formPath = v
    m.showPrompt(promptTemplateLanguage, m.formSectionTitle &
        " form · language", "")
  of promptTemplateLanguage:
    m.formLanguage = v
    m.showPrompt(promptTemplateFramework, m.formSectionTitle &
        " form · framework", "")
  of promptTemplateFramework:
    m.formFramework = v
    m.finishForm(templateFormCommand(m.formName, m.formDescription, m.formPath,
        m.formLanguage, m.formFramework))
  of promptNone:
    m.mode = modeDashboard

proc printable*(key: Key): string =
  if key.text.len > 0:
    return key.text
  if key.code == KeySpace:
    return " "
  ""

method update(m: WingApp; msg: Msg): (Model, Cmd) =
  if msg of WindowSizeMsg:
    let ws = WindowSizeMsg(msg)
    if ws.width > 0:
      m.width = ws.width
    if ws.height > 0:
      m.height = ws.height
    clampViewport(m.state, m.data, m.height)
    return (Model(m), nil)

  if msg of KeyPressMsg:
    let key = KeyPressMsg(msg).key

    case m.mode
    of modeOverlay:
      if key.matchString("up", "k"):
        m.overlayScroll = overlayScroll(m.overlayScroll, m.overlayLines.len, -1)
      elif key.matchString("down", "j"):
        m.overlayScroll = overlayScroll(m.overlayScroll, m.overlayLines.len, 1)
      elif key.matchString("pgup"):
        m.overlayScroll = overlayScroll(m.overlayScroll, m.overlayLines.len, -10)
      elif key.matchString("pgdown"):
        m.overlayScroll = overlayScroll(m.overlayScroll, m.overlayLines.len, 10)
      elif key.matchString("home"):
        m.overlayScroll = 0
      elif key.matchString("end"):
        m.overlayScroll = max(0, m.overlayLines.high)
      elif key.matchString("esc", "enter", "q", "Q", "ctrl+c"):
        m.mode = modeDashboard
      return (Model(m), nil)

    of modePrompt:
      if key.matchString("esc", "ctrl+c"):
        m.mode = modeDashboard
      elif key.matchString("enter"):
        m.acceptPrompt(m.promptValue)
      elif key.matchString("backspace", "ctrl+h"):
        if m.promptValue.len > 0:
          m.promptValue.setLen(m.promptValue.len - 1)
      elif key.matchString("up"):
        if m.promptHistory.len > 0:
          m.promptHistoryIndex = max(0, m.promptHistoryIndex - 1)
          m.promptValue = m.promptHistory[m.promptHistoryIndex]
      elif key.matchString("down"):
        if m.promptHistory.len > 0:
          m.promptHistoryIndex = min(m.promptHistory.len,
              m.promptHistoryIndex + 1)
          m.promptValue = if m.promptHistoryIndex >=
              m.promptHistory.len: "" else: m.promptHistory[
                  m.promptHistoryIndex]
      else:
        m.promptValue.add(printable(key))
      return (Model(m), nil)

    of modeDashboard:
      if key.matchString("q", "Q", "esc", "ctrl+c"):
        return (Model(m), Quit)
      elif key.matchString("?"):
        m.showOverlay("Help", helpText())
      elif key.matchString("r", "R"):
        m.data = loadDashboardData()
        m.state.message = "reloaded"
      elif key.matchString("left", "h"):
        dec m.state.section
        m.state.cursor = 0
        m.state.scroll = 0
        m.state.filter = ""
      elif key.matchString("right", "l", "tab"):
        inc m.state.section
        m.state.cursor = 0
        m.state.scroll = 0
        m.state.filter = ""
      elif key.matchString("up", "k"):
        dec m.state.cursor
      elif key.matchString("down", "j"):
        inc m.state.cursor
      elif key.matchString("pgup"):
        dec m.state.cursor, rowCapacity(m.height)
      elif key.matchString("pgdown"):
        inc m.state.cursor, rowCapacity(m.height)
      elif key.matchString("1", "2", "3", "4", "5", "6", "7", "8", "9"):
        # Numbered by what is on screen rather than one branch per key: sections are data, and a
        # key that jumps to a section that does not exist should do nothing rather than blank the
        # view.
        for index in 0 .. 8:
          if key.matchString($(index + 1)) and index <= m.data.sections.high:
            m.state.section = index
            m.state.cursor = 0
            m.state.scroll = 0
            m.state.filter = ""
      elif key.matchString("/"):
        m.showPrompt(promptFilter, "Filter " & currentSection(m.data,
            m.state).title, m.state.filter)
      elif key.matchString(":"):
        m.showPrompt(promptCommand, "Run wing command", "",
            m.state.commandHistory)
      elif key.matchString("a", "A"):
        m.startAddForm(currentSection(m.data, m.state))
      elif key.matchString("enter"):
        let row = selectedRow(m.data, m.state)
        let command = infoCommand(currentSection(m.data, m.state), row)
        if command.len > 0:
          let res = runCliCommand(command)
          m.showOverlay("Details (" & $res.code & ")", res.output)
      elif key.matchString("s", "S"):
        # The TUI cannot hand its terminal to ssh, so this shows the command instead of pretending
        # to run it -- copyable, and honest about which machine it would reach.
        let section = currentSection(m.data, m.state)
        let row = selectedRow(m.data, m.state)
        if row.len >= 2 and section.title == "Projects":
          let res = runCliCommand("where " & quoteShell(row[0] & ":" & row[1]))
          m.showOverlay("Where " & row[1] & " is", res.output)
        elif row.len >= 1 and section.title == "Machines":
          let res = runCliCommand("ssh " & quoteShell(row[0]) & " --dry-run")
          m.showOverlay("Shell into " & row[0], res.output)
      elif key.matchString("d", "D", "delete"):
        let section = currentSection(m.data, m.state)
        let row = selectedRow(m.data, m.state)
        let command = deleteCommand(section, row)
        if command.len > 0:
          m.deleteCommandText = command
          m.deleteItemName = row[0]
          m.showPrompt(promptDeleteConfirm, "Delete " & section.title &
              " item", "type yes to delete " & row[0])

  clampViewport(m.state, m.data, m.height)
  (Model(m), nil)

method view(m: WingApp): View =
  let base = newStyle().padding(1, 2).render(dashboardBody(m))
  var content = base
  case m.mode
  of modeOverlay:
    content = overlay(base, modal(m.overlayTitle, m.overlayLines,
        m.overlayScroll, m.width, m.height), m.width, m.height)
  of modePrompt:
    content = overlay(base, promptModal(m.promptTitle, m.promptValue,
        m.width, m.height), m.width, m.height)
  of modeDashboard:
    discard

  result = newView(content)
  result.altScreen = true
  result.windowTitle = "wing"

proc runTui*(args: seq[string] = @[]) =
  if hasFlag(args, ["-h", "--help"]):
    tuiHelp()
    return

  let nonInteractiveCommand = valueAfter(args, ["--command", "--exec"])
  if nonInteractiveCommand.len > 0:
    let res = runCliCommand(nonInteractiveCommand)
    stdout.write(res.output)
    quit(res.code)

  let data = loadDashboardData()
  if hasFlag(args, ["--snapshot"]):
    stdout.write(renderSnapshot(data))
    return

  discard newProgram(Model(WingApp(data: data, state: ViewState(section: 0,
      cursor: 0, scroll: 0), width: 80, height: 24))).run()
