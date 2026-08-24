## Renders the tab bar, rows, modals, and overlays.

import std/strutils

import boba
import boba/ansi/wrap
import boba/uv/styled

import ../types
import ./model
import ./state

proc dash*(s: string): string =
  if s.strip().len == 0 or s == "None":
    "—"
  else:
    s

proc cell*(bg, fg: Color; width: int; text: string; right = false;
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

proc titleColor*(title: string): Color =
  case title
  of "Projects": cPrimary
  of "Machines": cWarn
  of "Templates": cOk
  of "Sync": cTag
  else: cPrimary

proc sectionIcon*(title: string): string =
  case title
  of "Hosts": "⬢"
  of "Projects": "◆"
  of "Machines": "●"
  of "Templates": "◇"
  of "Sync": "⇄"
  else: "•"

proc rowParts*(section: DashboardSection; row: seq[string]): tuple[
    name, right, meta, desc: string] =
  let title = section.title
  result.name = if row.len > 0: row[0] else: ""
  case title
  of "Hosts":
    # [host, projects, languages, os]
    result.right = (if row.len > 1: row[1] else: "0") & " projects"
    # "no languages known" and "no projects here" are different things to say, and saying the
    # second when the first is true reads as an empty machine that is not empty.
    result.meta =
      if row.len > 2 and row[2].len > 0: row[2]
      elif row.len > 1 and row[1] == "0": "nothing registered here yet"
      else: "—"
    result.desc = if row.len > 3: dash(row[3]) else: "—"
  of "Projects":
    # [host, name, path, language] -- the project is the name, the host is where it is.
    result.name = if row.len > 1: row[1] else: ""
    result.right = if row.len > 3: dash(row[3]) else: "—"
    result.meta = "on " & (if row.len > 0: dash(row[0]) else: "—")
    result.desc = if row.len > 2: dash(row[2]) else: "—"
  of "Machines":
    # [name, user, hosts, tags, os]
    result.right = if row.len > 1: dash(row[1]) else: "—"
    result.meta = if row.len > 2: dash(row[2]) else: "—"
    result.desc = (if row.len > 4: dash(row[4]) else: "—") & "  ·  tags " &
        (if row.len > 3: dash(row[3]) else: "—")
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

proc renderRow*(section: DashboardSection; row: seq[string]; width, index: int;
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

proc tabBar*(data: DashboardData; state: ViewState; width: int): string =
  var parts: seq[string]
  for i, section in data.sections:
    let label = " " & section.title & " " & $section.rows.len & " "
    if i == state.section:
      parts.add newStyle().bold.foreground(cText).background(titleColor(
          section.title)).render(label)
    else:
      parts.add newStyle().foreground(cMuted).background(rowBgAlt).render(label)
  truncate(parts.join(" "), width, "…")

proc statusLine*(state: ViewState; width: int): string =
  let filterText = if state.filter.len == 0: "filter off" else: "/" & state.filter
  let message = if state.message.len == 0: "ready" else: state.message
  truncate(filterText & "  ·  " & message, width, "…")

proc helpLine*(width: int): string =
  newStyle().foreground(cMuted).render(truncate(
      "↑/↓ move · ←/→ tabs · enter details · s where · a add · d delete · / filter · : command · q quit",
      width, "…"))

proc dashboardBody*(m: WingApp): string =
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

proc stripAnsi*(s: string): string =
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

proc modal*(title: string; lines: seq[string]; scroll, width,
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

proc promptModal*(title, value: string; width, height: int): string =
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

proc overlay*(base, dialog: string; width, height: int): string =
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

proc renderSnapshot*(data: DashboardData): string =
  result.add("wing tui\n")
  result.add("data: " & data.dataDir & "\n")
  for section in data.sections:
    result.add(section.title & ": " & $section.rows.len & "\n")

proc helpText*(): string =
  """
Navigation:
  arrows/hjkl, Tab, 1-4

Actions:
  Enter  show details
  a      field-based add form
  d      delete selected item
  /      filter rows
  :      run any non-interactive wing command (successful commands are remembered)
  r      reload data
  ?      help
  q/Esc  quit
"""
