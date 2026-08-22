## Palette and the state records the dashboard model carries.

import boba

import ../types

let
  cPrimary* = basicColor(1)
  cOk* = basicColor(2)
  cWarn* = basicColor(3)
  cTag* = basicColor(6)
  cMuted* = basicColor(8)
  cText* = basicColor(15)
  rowBg* = extendedColor(232)
  rowBgAlt* = extendedColor(235)
  rowBgSelected* = extendedColor(237)
  panelBg* = extendedColor(233)

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
