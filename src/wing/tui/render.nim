## Renders the header, tab bar, rows, modals, and overlays.

import std/[strutils, times]

import boba
import boba/ansi/wrap
import boba/uv/styled

from ../ui import ago
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
  of "Tasks": cWarn
  of "Machines": cTag
  of "Templates": cOk
  of "Skills": cOk
  of "Agents": cPrimary
  of "Sync": cTag
  else: cPrimary

proc sectionIcon*(title: string): string =
  case title
  of "Projects": "◆"
  of "Tasks": "○"
  of "Machines": "●"
  of "Templates": "◇"
  of "Skills": "✦"
  of "Agents": "☺"
  of "Sync": "⇄"
  else: "•"

proc dueText(due, state: string): string =
  ## Plain words for a due date; the row colours it.
  if due.len == 0 or state == "done":
    return ""
  try:
    let today = parse(now().utc.format("yyyy-MM-dd"), "yyyy-MM-dd", utc())
    let days = (parse(due, "yyyy-MM-dd", utc()) - today).inDays
    if days < 0: "overdue " & $(-days) & "d"
    elif days == 0: "due today"
    elif days <= 3: "due in " & $days & "d"
    else: "due " & due
  except CatchableError:
    "due " & due

proc rowParts*(section: DashboardSection; row: seq[string]): tuple[
    name, right, meta, desc: string] =
  let title = section.title
  result.name = if row.len > 0: row[0] else: ""
  case title
  of "Projects":
    # [machine, name, path, language] -- the project is the name, the machine is where it is.
    result.name = if row.len > 1: row[1] else: ""
    result.right = if row.len > 3: dash(row[3]) else: "—"
    result.meta = "on " & (if row.len > 0: dash(row[0]) else: "—")
    result.desc = if row.len > 2: dash(row[2]) else: "—"
  of "Tasks":
    # [project, number, title, state, priority, plan, due, updated]
    if row.len < 8:
      return
    result.name = row[2]
    let due = dueText(row[6], row[3])
    result.right = if due.len > 0: due elif row[4] == "high" and row[3] !=
        "done": "high" else: row[3]
    result.meta = "@" & row[0] & "  #" & row[1] & (if row[5].len > 0: "  +" &
        row[5] else: "")
    result.desc = (if row[4] != "normal": row[4] & " priority  ·  " else: "") &
        "updated " & ago(row[7])
  of "Machines":
    # [name, user, addresses, projects, os]
    result.right = (if row.len > 3: row[3] else: "0") & " projects"
    result.meta = if row.len > 2: dash(row[2]) else: "—"
    result.desc = (if row.len > 4: dash(row[4]) else: "—") & "  ·  " &
        (if row.len > 1: dash(row[1]) else: "—")
  of "Templates":
    result.right = if row.len > 3: dash(row[3]) else: "—"
    result.meta = if row.len > 1: dash(row[1]) else: "—"
    result.desc = if row.len > 2: dash(row[2]) else: "—"
  of "Agents":
    # [name, tools written for, role, notes]
    let tools = if row.len > 1: row[1].splitWhitespace() else: @[]
    result.right = $tools.len & (if tools.len == 1: " tool" else: " tools")
    result.meta = if row.len > 2: dash(row[2]) else: "—"
    var written = "no coding tool installed here"
    if tools.len > 0:
      written = "written for " & tools.join(", ")
    if row.len > 3 and row[3] != "0":
      written.add("  ·  " & row[3] & " notes")
    result.desc = written
  of "Skills":
    # [name, linked, description]
    let linked = if row.len > 1: row[1] else: ""
    result.right = linked.split(' ')[0] & " agents"
    result.meta = if row.len > 2: dash(row[2]) else: "—"
    result.desc = if linked.contains(' ') and linked.split(' ', 1)[1].len >
        0: "linked: " & linked.split(' ', 1)[1]
                  else: "not linked"
  of "Sync":
    result.right = if row.len > 4: dash(row[4]) else: "—"
    result.meta = if row.len > 2: dash(row[2]) else: "—"
    result.desc = if row.len > 3: dash(row[3]) else: "—"
  else:
    result.right = if row.len > 1: dash(row[1]) else: "—"
    result.meta = row.join(" · ")
    result.desc = ""

proc rowIcon(section: DashboardSection; row: seq[string]): (string, Color) =
  ## A task shows its state; everything else its tab's mark.
  if section.title == "Tasks" and row.len > 3:
    case row[3]
    of "doing": return ("◐", cWarn)
    of "done": return ("●", cOk)
    else: return ("○", cTag)
  (sectionIcon(section.title), titleColor(section.title))

proc rightColor(section: DashboardSection; right: string): Color =
  if section.title == "Tasks":
    if right.startsWith("overdue") or right == "high": return cBad
    if right.startsWith("due"): return cWarn
    if right == "done": return cOk
    return cMuted
  cTag

proc renderRow*(section: DashboardSection; row: seq[string]; width, index: int;
    selected: bool): string =
  let bg =
    if selected: rowBgSelected
    elif index mod 2 == 1: rowBgAlt
    else: rowBg
  let accent = titleColor(section.title)
  let marker = if selected: "▌ " else: "  "
  let bar = newStyle().background(bg).foreground(accent).render(marker)
  let inner = max(width - 2, 20)
  let parts = rowParts(section, row)
  let (icon, iconColor) = rowIcon(section, row)
  let done = section.title == "Tasks" and row.len > 3 and row[3] == "done"

  let iconCol = 2
  let rightCol = min(max(14, inner div 4), 28)
  let nameCol = max(8, inner - iconCol - rightCol)
  let line1 = bar &
      cell(bg, iconColor, iconCol, icon) &
      cell(bg, if done: cMuted elif selected: accent else: cText, nameCol,
          parts.name, bold = not done) &
      cell(bg, rightColor(section, parts.right), rightCol, parts.right, right = true)

  let line2 = bar & cell(bg, cMuted, inner, parts.meta)
  let line3 = bar & cell(bg, extendedColor(240), inner, parts.desc, italic = true)
  line1 & "\n" & line2 & "\n" & line3

proc header*(data: DashboardData; width: int): string =
  ## wing, and which server it is talking to.
  let brand = newStyle().bold.foreground(cPrimary).render("◆ wing")
  let where =
    if data.server.len == 0:
      newStyle().foreground(cMuted).render("  local only · wing server login URL")
    elif data.serverError.len > 0:
      newStyle().foreground(cBad).render("  " & data.server & " is not answering")
    else:
      newStyle().foreground(cOk).render("  ●") & newStyle().foreground(
          cMuted).render(" " & data.server)
  truncate(brand & where, width, "…")

proc tabBar*(data: DashboardData; state: ViewState; width: int): string =
  var parts: seq[string]
  for i, section in data.sections:
    let label = " " & $(i + 1) & " " & section.title & " " & $section.rows.len & " "
    if i == state.section:
      parts.add newStyle().bold.foreground(extendedColor(234)).background(
          titleColor(section.title)).render(label)
    else:
      parts.add newStyle().foreground(cMuted).background(rowBgAlt).render(label)
  truncate(parts.join(" "), width, "…")

proc statusLine*(state: ViewState; width: int): string =
  let filterText = if state.filter.len == 0: "" else: "filter /" &
      state.filter & "  ·  "
  let message = if state.message.len == 0: "ready" else: state.message
  let color = if message.startsWith("failed"): cBad elif message.startsWith(
      "ok"): cOk else: cMuted
  newStyle().foreground(cMuted).render(filterText) &
      newStyle().foreground(color).render(truncate(message, max(10, width -
          filterText.len), "…"))

proc keysFor*(title: string): string =
  ## The keys that do something on this tab, then the ones that always do.
  let own = case title
    of "Tasks": "a add · s start · x done · o reopen · d delete · enter show"
    of "Skills": "p pull · enter files · d delete on server"
    of "Agents": "p pull · enter files · d delete on server"
    of "Projects": "a add · s where · d delete · enter details"
    of "Machines": "a add · s ssh · d delete · enter details"
    of "Templates": "a add · d delete · enter details"
    else: "enter details · d delete"
  own & " · / filter · : command · r reload · ←/→ tabs · ? help · q quit"

proc helpLine*(title: string; width: int): string =
  newStyle().foreground(cMuted).render(truncate(keysFor(title), width, "…"))

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
  lines.add header(m.data, width)
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
  lines.add helpLine(section.title, width)
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
  let bodyRows = max(3, min(height - 10, 18))
  let titleBar = newStyle().bold.foreground(extendedColor(234)).background(
      cPrimary).render(" " & title & " ")

  var body: seq[string]
  body.add titleBar
  body.add ""
  for i in 0 ..< bodyRows:
    let lineIndex = scroll + i
    let text = if lineIndex < lines.len: lines[lineIndex] else: ""
    body.add newStyle().foreground(cText).render(truncate(text, max(8,
        modalWidth - 4), "…"))
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
  let titleBar = newStyle().bold.foreground(extendedColor(234)).background(
      cPrimary).render(" " & title & " ")
  let input = newStyle().foreground(cText).background(rowBgSelected).width(
      max(12, modalWidth - 8)).render("› " & value & "▏")
  let body = titleBar & "\n\n" & input & "\n\n" &
      newStyle().foreground(cMuted).render(
      "enter accepts · esc cancels · backspace deletes")
  newStyle().padding(1, 2).foreground(cPrimary).background(panelBg).withBorder(
      roundedBorder()).render(body)

proc overlay*(base, dialog: string; width, height: int): string =
  let w = max(width, 1)
  let h = max(height, 1)
  let dimmed = newStyle().foreground(extendedColor(238)).render(stripAnsi(base))
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
  result.add("server: " & (if data.server.len > 0: data.server else: "none") & "\n")
  for section in data.sections:
    result.add(section.title & ": " & $section.rows.len & "\n")

proc helpText*(): string =
  """
Navigation:
  ←/→ or h/l, Tab     switch tabs (or 1-7)
  ↑/↓ or j/k          move; PgUp/PgDn move faster

Everywhere:
  Enter   show details
  a       add (a form; on Tasks one line: "@project text +plan !high")
  d       delete the selected item, after confirming
  /       filter rows
  :       run any non-interactive wing command
  r       reload from disk and the wing server
  ?       this help
  q/Esc   quit

Tasks:
  s start · x done · o reopen

Agents and Skills:
  p pull from the wing server and link into every agent
"""
