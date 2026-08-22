## Domain records shared by the store, command, and TUI layers.

type
  Host* = object
    ip*: string
    port*: string
    iface*: string

  Machine* = object
    name*: string
    username*: string
    key*: string
    proxyJump*: string
    forwardAgent*: bool
    hosts*: seq[Host]

  Project* = object
    name*: string
    path*: string
    namespace*: string
    templateName*: string
    description*: string
    language*: string
    framework*: string
    tags*: seq[string]
    createdAt*: string
    updatedAt*: string

  Template* = object
    name*: string
    description*: string
    path*: string
    language*: string
    framework*: string
    tags*: seq[string]
    createdAt*: string
    updatedAt*: string

  BuiltinTemplate* = object
    name*: string
    description*: string
    dir*: string
    language*: string
    framework*: string
    tags*: string
    nixPackages*: string
    flavours*: string
    defaultFlavour*: string

  SyncTarget* = object
    name*: string
    project*: string
    machine*: string
    iface*: string
    remotePath*: string
    direction*: string
    delete*: bool
    exclude*: seq[string]
    createdAt*: string
    updatedAt*: string

  DashboardSection* = object
    title*: string
    empty*: string
    headers*: seq[string]
    rows*: seq[seq[string]]

  DashboardData* = object
    dataDir*: string
    sections*: seq[DashboardSection]
