## Palette and the state records the dashboard model carries.

import boba

import ../types

# The CLI's palette (ui.nim), so the dashboard and the commands read as one tool.
let
  cPrimary* = extendedColor(141)
  cOk* = extendedColor(114)
  cWarn* = extendedColor(179)
  cBad* = extendedColor(203)
  cTag* = extendedColor(117)
  cMuted* = extendedColor(244)
  cText* = extendedColor(252)
  rowBg* = extendedColor(234)
  rowBgAlt* = extendedColor(235)
  rowBgSelected* = extendedColor(237)
  panelBg* = extendedColor(235)

type
  ViewState* = object
    section*: int
    cursor*: int
    scroll*: int
    filter*: string
    message*: string
    commandHistory*: seq[string]

  CommandResult* = object
    code*: int
    output*: string

  FormBuildResult* = object
    ok*: bool
    command*: string
    error*: string

  UiMode* = enum
    modeDashboard
    modeOverlay
    modePrompt

  PromptKind* = enum
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
    promptTaskAdd

  WingApp* = ref object of Model
    data*: DashboardData
    state*: ViewState
    width*: int
    height*: int
    mode*: UiMode
    overlayTitle*: string
    overlayLines*: seq[string]
    overlayScroll*: int
    promptKind*: PromptKind
    promptTitle*: string
    promptValue*: string
    promptHistory*: seq[string]
    promptHistoryIndex*: int
    deleteCommandText*: string
    deleteItemName*: string
    formSectionTitle*: string
    formName*: string
    formPath*: string
    formNamespace*: string
    formLanguage*: string
    formFramework*: string
    formTags*: string
    formDescription*: string
    formUsername*: string
    formKey*: string
    formHost*: string
