## Cursor, filter, and viewport arithmetic over the dashboard sections.

import std/strutils

import ../types
import ./model

proc clampInt*(value, low, high: int): int =
  if high < low:
    return low
  if value < low:
    low
  elif value > high:
    high
  else:
    value

proc filteredRows*(section: DashboardSection; filter: string): seq[seq[string]] =
  let needle = filter.strip().toLowerAscii()
  if needle.len == 0:
    return section.rows
  for row in section.rows:
    if row.join(" ").toLowerAscii().contains(needle):
      result.add(row)

proc currentSection*(data: DashboardData; state: ViewState): DashboardSection =
  data.sections[state.section]

proc sectionRows*(data: DashboardData; state: ViewState): seq[seq[string]] =
  if data.sections.len == 0:
    return @[]
  filteredRows(currentSection(data, state), state.filter)

proc selectedRow*(data: DashboardData; state: ViewState): seq[string] =
  let rows = sectionRows(data, state)
  if rows.len == 0:
    @[]
  else:
    rows[clampInt(state.cursor, 0, rows.high)]

proc clampState*(state: var ViewState; data: DashboardData) =
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

proc rowCapacity*(height: int): int =
  let contentHeight = max(height - 2, 10)
  max((contentHeight - 4) div 3, 1)

proc clampViewport*(state: var ViewState; data: DashboardData; height: int) =
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
