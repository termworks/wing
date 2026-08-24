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
    # What this machine is, so a command can name a group rather than a list: `--tag gpu` is one
    # word where naming four machines is four words that go stale as the fleet changes.
    tags*: seq[string]
    hosts*: seq[Host]

  Project* = object
    name*: string
    path*: string
    # Which machine the path is on; empty means this one. A project registry that cannot say where
    # a project lives is a list of paths that are only true on one computer.
    machine*: string
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

  # A flavour is a named variant of one template: its own Nix packages and its own note about the
  # environment it sets up. Before this was data, "does this template have variants" was answered
  # by comparing the template's name to "python" inside the compiler.
  TemplateFlavour* = object
    name*: string
    nixPackages*: string
    environment*: string

  # What a template.lua declares about itself. Replaces the compiled-in BuiltinTemplate record.
  TemplateSpec* = object
    name*: string
    # The template root this was declared in. A spec resolves its own files, because with a search
    # path of roots the root is a property of the declaration, not of the call site.
    root*: string
    description*: string
    dir*: string
    language*: string
    framework*: string
    tags*: seq[string]
    nixPackages*: string
    # What the dev shell gives you, in a sentence. A flavourless template says it here; one with
    # flavours says it per flavour, because that is what differs between them.
    environment*: string
    flavours*: seq[TemplateFlavour]
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
