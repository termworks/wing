import std/[cmdline, os, osproc, streams, strutils]

import boba
import boba/ansi/wrap
import boba/uv/styled

import devpilot

let
  cPrimary = basicColor(1)
  cOk = basicColor(2)
  cWarn = basicColor(3)
  cTag = basicColor(6)
  cMuted = basicColor(8)
  cText = basicColor(15)
  rowBg = extendedColor(232)
  rowBgAlt = extendedColor(235)
  rowBgSelected = extendedColor(237)
  panelBg = extendedColor(233)

type
  ViewState = object
    section: int
    cursor: int
    scroll: int
    filter: string
    message: string
    commandHistory: seq[string]

  CommandResult = object
    code: int
    output: string

  FormBuildResult* = object
    ok*: bool
    command*: string
    error*: string

  UiMode = enum
    modeDashboard
    modeOverlay
    modePrompt

  PromptKind = enum
    promptNone
    promptFilter
    promptCommand
    promptDeleteConfirm
    promptProjectName
    promptProjectPath
    promptProjectNamespace
    promptProjectLanguage
    promptProjectFramework
    promptProjectTags
    promptMachineName
    promptMachineUsername
    promptMachineKey
    promptMachineHost
    promptTemplateName
    promptTemplateDescription
    promptTemplatePath
    promptTemplateLanguage
    promptTemplateFramework

  DevpilotApp = ref object of Model
    data: DashboardData
    state: ViewState
    width: int
    height: int
    mode: UiMode
    overlayTitle: string
    overlayLines: seq[string]
    overlayScroll: int
    promptKind: PromptKind
    promptTitle: string
    promptValue: string
    promptHistory: seq[string]
    promptHistoryIndex: int
    deleteCommandText: string
    deleteItemName: string
    formSectionTitle: string
    formName: string
    formPath: string
    formNamespace: string
    formLanguage: string
    formFramework: string
    formTags: string
    formDescription: string
    formUsername: string
    formKey: string
    formHost: string

proc tuiHelp() =
  echo """
Usage: dp tui [--snapshot] [--command COMMAND]

Options:
  --snapshot         Print a non-interactive dashboard summary
  --command COMMAND  Run a devpilot command through the TUI command runner
  -h, --help         Print help information

Keys:
  Left/Right, h/l, Tab, 1-4   Switch sections
  Up/Down, j/k                Move selection
  PageUp/PageDown             Move faster
  /                           Filter current view
  :                           Command palette; type any normal dp command
  a                           Open add form for the current section
  d                           Delete selected item after confirmation
  Enter                       Show selected item details
  r                           Reload data
  ?                           Show this help in the TUI
  q, Esc, Ctrl-C              Quit
"""

proc hasFlag(args: seq[string]; names: openArray[string]): bool =
  for arg in args:
    for name in names:
      if arg == name:
        return true

proc valueAfter(args: seq[string]; names: openArray[string]): string =
  for i, arg in args:
    for name in names:
      if arg == name and i + 1 < args.len:
        return args[i + 1]
      let prefix = name & "="
      if arg.startsWith(prefix):
        return arg[prefix.len .. ^1]

proc formError(message: string): FormBuildResult =
  FormBuildResult(ok: false, error: message)

proc formCommand(command: string): FormBuildResult =
  FormBuildResult(ok: true, command: command)

proc requireField(value, label: string): string =
  if value.strip().len == 0:
    label & " is required"
  else:
    ""

proc tagArgs(tags: string): string =
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

proc clampInt(value, low, high: int): int =
  if high < low:
    return low
  if value < low:
    low
  elif value > high:
    high
  else:
    value

proc filteredRows(section: DashboardSection; filter: string): seq[seq[string]] =
  let needle = filter.strip().toLowerAscii()
  if needle.len == 0:
    return section.rows
  for row in section.rows:
    if row.join(" ").toLowerAscii().contains(needle):
      result.add(row)

proc currentSection(data: DashboardData; state: ViewState): DashboardSection =
  data.sections[state.section]

proc sectionRows(data: DashboardData; state: ViewState): seq[seq[string]] =
  if data.sections.len == 0:
    return @[]
  filteredRows(currentSection(data, state), state.filter)

proc selectedRow(data: DashboardData; state: ViewState): seq[string] =
  let rows = sectionRows(data, state)
  if rows.len == 0:
    @[]
  else:
    rows[clampInt(state.cursor, 0, rows.high)]

proc clampState(state: var ViewState; data: DashboardData) =
  if data.sections.len == 0:
    state.section = 0
    state.cursor = 0
    state.scroll = 0
    return
  state.section = clampInt(state.section, 0, data.sections.high)
  let rows = sectionRows(data, state)
  if rows.len == 0:
    state.cursor = 0
    state.scroll = 0
  else:
    state.cursor = clampInt(state.cursor, 0, rows.high)
    state.scroll = clampInt(state.scroll, 0, state.cursor)

proc rowCapacity(height: int): int =
  let contentHeight = max(height - 2, 10)
  max((contentHeight - 4) div 3, 1)

proc clampViewport(state: var ViewState; data: DashboardData; height: int) =
  clampState(state, data)
  let rows = sectionRows(data, state)
  if rows.len == 0:
    state.scroll = 0
    return
  let visible = rowCapacity(height)
  if state.cursor < state.scroll:
    state.scroll = state.cursor
  elif state.cursor >= state.scroll + visible:
    state.scroll = max(0, state.cursor - visible + 1)
  state.scroll = clampInt(state.scroll, 0, max(0, rows.len - visible))

proc dash(s: string): string =
  if s.strip().len == 0 or s == "None":
    "—"
  else:
    s

proc cell(bg, fg: Color; width: int; text: string; right = false;
    bold = false; italic = false): string =
  let w = max(width, 1)
  var st = newStyle().background(bg).foreground(fg).width(w)
  if right:
    st = st.align(alRight)
  if bold:
    st = st.bold
  if italic:
    st = st.italic
  st.render(truncate(text, w, "…"))

proc titleColor(title: string): Color =
  case title
  of "Projects": cPrimary
  of "Machines": cWarn
  of "Templates": cOk
  of "Sync": cTag
  else: cPrimary

proc sectionIcon(title: string): string =
  case title
  of "Projects": "◆"
  of "Machines": "●"
  of "Templates": "◇"
  of "Sync": "⇄"
  else: "•"

proc rowParts(section: DashboardSection; row: seq[string]): tuple[
    name, right, meta, desc: string] =
  let title = section.title
  result.name = if row.len > 0: row[0] else: ""
  case title
  of "Projects":
    result.right = if row.len > 3: dash(row[3]) else: "—"
    result.meta = "namespace " & (if row.len > 1: dash(row[1]) else: "—")
    result.desc = if row.len > 2: dash(row[2]) else: "—"
  of "Machines":
    result.right = if row.len > 1: dash(row[1]) else: "—"
    result.meta = if row.len > 2: dash(row[2]) else: "—"
    result.desc = "key " & (if row.len > 3: dash(row[3]) else: "—")
  of "Templates":
    result.right = if row.len > 3: dash(row[3]) else: "—"
    result.meta = if row.len > 1: dash(row[1]) else: "—"
    result.desc = if row.len > 2: dash(row[2]) else: "—"
  of "Sync":
    result.right = if row.len > 4: dash(row[4]) else: "—"
    result.meta = if row.len > 2: dash(row[2]) else: "—"
    result.desc = if row.len > 3: dash(row[3]) else: "—"
  else:
    result.right = if row.len > 1: dash(row[1]) else: "—"
    result.meta = row.join(" · ")
    result.desc = ""

proc renderRow(section: DashboardSection; row: seq[string]; width, index: int;
    selected: bool): string =
  let bg =
    if selected: rowBgSelected
    elif index mod 2 == 1: rowBgAlt
    else: rowBg
  let accent = titleColor(section.title)
  let marker = if selected: "┃ " else: "  "
  let bar = newStyle().background(bg).foreground(accent).render(marker)
  let inner = max(width - 2, 20)
  let parts = rowParts(section, row)

  let iconCol = 2
  let rightCol = min(max(14, inner div 4), 28)
  let nameCol = max(8, inner - iconCol - rightCol)
  let line1 = bar &
      cell(bg, accent, iconCol, sectionIcon(section.title)) &
      cell(bg, if selected: accent else: cText, nameCol, parts.name,
          bold = true) &
      cell(bg, cTag, rightCol, parts.right, right = true)

  let line2 = bar & cell(bg, cMuted, inner, parts.meta)
  let line3 = bar & cell(bg, cMuted, inner, parts.desc, italic = true)
  line1 & "\n" & line2 & "\n" & line3

proc tabBar(data: DashboardData; state: ViewState; width: int): string =
  var parts: seq[string]
  for i, section in data.sections:
    let label = " " & section.title & " " & $section.rows.len & " "
    if i == state.section:
      parts.add newStyle().bold.foreground(cText).background(titleColor(
          section.title)).render(label)
    else:
      parts.add newStyle().foreground(cMuted).background(rowBgAlt).render(label)
  truncate(parts.join(" "), width, "…")

proc statusLine(state: ViewState; width: int): string =
  let filterText = if state.filter.len == 0: "filter off" else: "/" & state.filter
  let message = if state.message.len == 0: "ready" else: state.message
  truncate(filterText & "  ·  " & message, width, "…")

proc helpLine(width: int): string =
  newStyle().foreground(cMuted).render(truncate(
      "↑/↓ move · ←/→ tabs · enter details · a add · d delete · / filter · : command · r reload · q quit",
      width, "…"))

proc dashboardBody(m: DevpilotApp): string =
  var state = m.state
  clampViewport(state, m.data, m.height)
  m.state = state

  let width = max(m.width - 4, 40)
  let contentHeight = max(m.height - 2, 10)
  let section = currentSection(m.data, state)
  let rows = sectionRows(m.data, state)
  let visibleRows = rowCapacity(m.height)

  var lines: seq[string]
  lines.add tabBar(m.data, state, width)
  lines.add ""

  if rows.len == 0:
    let empty = newStyle().foreground(cMuted).padding(1, 2).withBorder(
        roundedBorder()).render(section.empty)
    for line in empty.split('\n'):
      lines.add truncate(line, width, "…")
  else:
    let last = min(state.scroll + visibleRows, rows.len)
    for rowIndex in state.scroll ..< last:
      for line in renderRow(section, rows[rowIndex], width, rowIndex,
          rowIndex == state.cursor).split('\n'):
        lines.add line

  while lines.len < contentHeight - 2:
    lines.add ""
  lines.add statusLine(state, width)
  lines.add helpLine(width)
  if lines.len > contentHeight:
    lines = lines[0 ..< contentHeight]
  lines.join("\n")

proc stripAnsi(s: string): string =
  var i = 0
  while i < s.len:
    if s[i] == '\x1b':
      if i + 1 < s.len and s[i + 1] == '[':
        i += 2
        while i < s.len and (s[i] < '\x40' or s[i] > '\x7e'):
          inc i
        if i < s.len:
          inc i
      elif i + 1 < s.len and s[i + 1] == ']':
        i += 2
        while i < s.len and s[i] != '\x07':
          inc i
        if i < s.len:
          inc i
      else:
        i += 2
    else:
      result.add s[i]
      inc i

proc modal(title: string; lines: seq[string]; scroll, width,
    height: int): string =
  let modalWidth = max(36, min(width - 6, 96))
  let bodyRows = max(3, min(height - 10, 16))
  let titleBar = newStyle().bold.foreground(cText).background(cPrimary).render(
      " " & title & " ")

  var body: seq[string]
  body.add titleBar
  body.add ""
  for i in 0 ..< bodyRows:
    let lineIndex = scroll + i
    let text = if lineIndex < lines.len: lines[lineIndex] else: ""
    body.add truncate(text, max(8, modalWidth - 4), "…")
  body.add ""
  if lines.len > bodyRows:
    body.add newStyle().foreground(cMuted).render(
        "↑/↓ scroll · pgup/pgdn jump · esc close")
  else:
    body.add newStyle().foreground(cMuted).render("enter/esc close")

  newStyle().padding(1, 2).foreground(cPrimary).background(panelBg).withBorder(
      roundedBorder()).render(body.join("\n"))

proc promptModal(title, value: string; width, height: int): string =
  let modalWidth = max(36, min(width - 6, 96))
  let titleBar = newStyle().bold.foreground(cText).background(cPrimary).render(
      " " & title & " ")
  let input = newStyle().foreground(cText).background(rowBgSelected).width(
      max(12, modalWidth - 8)).render("> " & value)
  let body = titleBar & "\n\n" & input & "\n\n" &
      newStyle().foreground(cMuted).render(
      "enter accepts · esc cancels · backspace deletes")
  newStyle().padding(1, 2).foreground(cPrimary).background(panelBg).withBorder(
      roundedBorder()).render(body)

proc overlay(base, dialog: string; width, height: int): string =
  let w = max(width, 1)
  let h = max(height, 1)
  let dimmed = newStyle().foreground(cMuted).render(stripAnsi(base))
  var buf = newBuffer(w, h)
  newStyledString(dimmed).draw(buf)

  let dialogLines = dialog.split('\n')
  var dialogWidth = 0
  for line in dialogLines:
    dialogWidth = max(dialogWidth, stringWidth(line))
  var dialogBuf = newBuffer(max(dialogWidth, 1), max(dialogLines.len, 1))
  newStyledString(dialog).draw(dialogBuf)
  buf.blit(dialogBuf, max((w - dialogWidth) div 2, 0),
      max((h - dialogLines.len) div 2, 0))
  buf.render.replace("\r\n", "\n")

proc overlayScroll*(current, lineCount, delta: int): int =
  clampInt(current + delta, 0, max(0, lineCount - 1))

proc runCliCommand(commandInput: string): CommandResult =
  var command = commandInput.strip()
  if command.startsWith("dp "):
    command = command[3 .. ^1].strip()
  if command.len == 0:
    return CommandResult(code: 1, output: "Empty command")

  var args: seq[string]
  try:
    args = parseCmdLine(command)
  except ValueError as e:
    return CommandResult(code: 1, output: e.msg)

  if args.len == 0:
    return CommandResult(code: 1, output: "Empty command")
  if args[0] in ["tui", "ui", "dashboard"]:
    return CommandResult(code: 1, output: "Nested TUI commands are disabled inside the TUI")
  if args.len >= 2 and args[0] in ["machine", "m", "machines", "host",
      "hosts"] and args[1] in ["connect", "c", "ssh"]:
    return CommandResult(code: 1, output: "Interactive ssh is disabled inside the TUI; run this from the normal CLI")

  try:
    let process = startProcess(getAppFilename(), args = args,
        options = {poStdErrToStdOut})
    let output = process.outputStream.readAll()
    let code = process.waitForExit()
    process.close()
    result = CommandResult(code: code, output: output)
  except OSError as e:
    result = CommandResult(code: 1, output: e.msg)

proc infoCommand(section: DashboardSection; row: seq[string]): string =
  if row.len == 0:
    return ""
  case section.title
  of "Projects":
    let namespace = if row.len > 1: row[1] else: "default"
    "project --namespace " & quoteShell(namespace) & " info " & quoteShell(row[0])
  of "Machines":
    "machine info " & quoteShell(row[0])
  of "Templates":
    "template info " & quoteShell(row[0])
  of "Sync":
    "sync info " & quoteShell(row[0])
  else:
    ""

proc deleteCommand(section: DashboardSection; row: seq[string]): string =
  if row.len == 0:
    return ""
  case section.title
  of "Projects":
    let namespace = if row.len > 1: row[1] else: "default"
    "project --namespace " & quoteShell(namespace) & " remove " & quoteShell(row[0])
  of "Machines":
    "machine remove " & quoteShell(row[0])
  of "Templates":
    "template remove " & quoteShell(row[0])
  of "Sync":
    "sync remove " & quoteShell(row[0])
  else:
    ""

proc renderSnapshot(data: DashboardData): string =
  result.add("devpilot tui\n")
  result.add("data: " & data.dataDir & "\n")
  for section in data.sections:
    result.add(section.title & ": " & $section.rows.len & "\n")

proc helpText(): string =
  """
Navigation:
  arrows/hjkl, Tab, 1-4

Actions:
  Enter  show details
  a      field-based add form
  d      delete selected item
  /      filter rows
  :      run any non-interactive dp command (successful commands are remembered)
  r      reload data
  ?      help
  q/Esc  quit
"""

proc showOverlay(m: DevpilotApp; title, content: string) =
  m.mode = modeOverlay
  m.overlayTitle = title
  m.overlayLines = if content.len == 0: @[
      "No output."] else: content.splitLines()
  m.overlayScroll = 0

proc showPrompt(m: DevpilotApp; kind: PromptKind; title, initial: string;
    history: seq[string] = @[]) =
  m.mode = modePrompt
  m.promptKind = kind
  m.promptTitle = title
  m.promptValue = initial
  m.promptHistory = history
  m.promptHistoryIndex = history.len

proc runAndOverlay(m: DevpilotApp; command, titlePrefix: string) =
  let res = runCliCommand(command)
  m.data = loadDashboardData()
  m.state.message = if res.code == 0: "ok: " & command else: "failed: " & command
  m.showOverlay(titlePrefix & " (" & $res.code & ")", res.output)

proc startAddForm(m: DevpilotApp; section: DashboardSection) =
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
        "Use the CLI — sync targets need several fields:\n  dp sync add NAME --project P --machine M --remote PATH")
  else:
    m.showOverlay("Validation", "Unsupported form section: " & section.title)

proc finishForm(m: DevpilotApp; built: FormBuildResult) =
  if built.ok:
    m.runAndOverlay(built.command, "Add result")
  elif built.error.len > 0:
    m.state.message = built.error
    m.showOverlay("Validation", built.error)
  else:
    m.mode = modeDashboard

proc acceptPrompt(m: DevpilotApp; value: string) =
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

proc printable(key: Key): string =
  if key.text.len > 0:
    return key.text
  if key.code == KeySpace:
    return " "
  ""

method update(m: DevpilotApp; msg: Msg): (Model, Cmd) =
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
      elif key.matchString("1"):
        m.state.section = 0
        m.state.cursor = 0
        m.state.scroll = 0
        m.state.filter = ""
      elif key.matchString("2"):
        m.state.section = 1
        m.state.cursor = 0
        m.state.scroll = 0
        m.state.filter = ""
      elif key.matchString("3"):
        m.state.section = 2
        m.state.cursor = 0
        m.state.scroll = 0
        m.state.filter = ""
      elif key.matchString("4"):
        m.state.section = 3
        m.state.cursor = 0
        m.state.scroll = 0
        m.state.filter = ""
      elif key.matchString("/"):
        m.showPrompt(promptFilter, "Filter " & currentSection(m.data,
            m.state).title, m.state.filter)
      elif key.matchString(":"):
        m.showPrompt(promptCommand, "Run devpilot command", "",
            m.state.commandHistory)
      elif key.matchString("a", "A"):
        m.startAddForm(currentSection(m.data, m.state))
      elif key.matchString("enter"):
        let row = selectedRow(m.data, m.state)
        let command = infoCommand(currentSection(m.data, m.state), row)
        if command.len > 0:
          let res = runCliCommand(command)
          m.showOverlay("Details (" & $res.code & ")", res.output)
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

method view(m: DevpilotApp): View =
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
  result.windowTitle = "devpilot"

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

  discard newProgram(Model(DevpilotApp(data: data, state: ViewState(section: 0,
      cursor: 0, scroll: 0), width: 80, height: 24))).run()
