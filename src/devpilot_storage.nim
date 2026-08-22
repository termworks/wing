import std/[os, strutils, times]

const
  SchemaVersion* = 1
  StorageFiles* = [
    "projects.toml",
    "machines.toml",
    "templates.toml",
    "syncs.toml"
  ]

proc storageStamp(): string =
  getTime().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")

proc safeStamp(value: string): string =
  value
    .replace(":", "")
    .replace("-", "")
    .replace("T", "-")
    .replace("Z", "Z")

proc schemaHeader*(): string =
  "schema_version = " & $SchemaVersion & "\n\n"

proc defaultStorageContent(fileName: string): string =
  case fileName
  of "projects.toml":
    schemaHeader() & "projects = []\n"
  of "machines.toml":
    schemaHeader() & "machines = []\n"
  of "templates.toml":
    schemaHeader() & "templates = []\n"
  of "syncs.toml":
    schemaHeader() & "syncs = []\n"
  else:
    schemaHeader()

proc dataRoot*(): string =
  let xdgData = getEnv("XDG_DATA_HOME")
  if xdgData.len > 0:
    result = xdgData / "devpilot"
  else:
    result = getHomeDir() / ".local" / "share" / "devpilot"
  createDir(result)

proc configPath*(fileName: string): string =
  dataRoot() / fileName

proc parseSchemaVersion(content, path: string): int =
  result = 0
  for rawLine in content.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith("#"):
      continue
    if line.startsWith("["):
      return
    let idx = line.find('=')
    if idx < 0:
      continue
    let key = line[0 ..< idx].strip()
    if key != "schema_version":
      continue
    let rawValue = line[idx + 1 .. ^1].strip()
    try:
      result = parseInt(rawValue)
    except ValueError:
      raise newException(ValueError,
          "Invalid schema_version in " & path & ": " & rawValue)
    return

proc validateSchema(content, path: string) =
  let version = parseSchemaVersion(content, path)
  if version > SchemaVersion:
    raise newException(ValueError,
        "Unsupported schema version " & $version & " in " & path &
        " (supported: " & $SchemaVersion & ")")

proc readConfig*(path: string): string =
  if not fileExists(path):
    return ""
  result = readFile(path)
  validateSchema(result, path)

proc atomicWriteFile*(path, content: string) =
  createDir(parentDir(path))
  let tmpPath = path & ".tmp." & $getCurrentProcessId()
  var file: File
  if not open(file, tmpPath, fmWrite):
    raise newException(IOError, "Unable to open temp file for write: " & tmpPath)
  try:
    file.write(content)
    file.flushFile()
    file.close()
    moveFile(tmpPath, path)
  except CatchableError:
    try:
      file.close()
    except CatchableError:
      discard
    if fileExists(tmpPath):
      removeFile(tmpPath)
    raise

proc ensureFile*(path, defaultContent: string) =
  createDir(parentDir(path))
  if (not fileExists(path)) or getFileSize(path) == 0:
    atomicWriteFile(path, defaultContent)

proc copyStorageFile(src, dst: string) =
  createDir(parentDir(dst))
  if fileExists(src):
    copyFile(src, dst)
  else:
    writeFile(dst, defaultStorageContent(splitPath(dst).tail))

proc createBackup*(destination = ""): string =
  let root = dataRoot()
  let stamp = storageStamp()
  result =
    if destination.len > 0: destination
    else: root / "backups" / ("devpilot-backup-" & safeStamp(stamp))

  if fileExists(result):
    raise newException(IOError, "Backup path is a file: " & result)
  if dirExists(result):
    raise newException(IOError, "Backup path already exists: " & result)

  createDir(result)
  var manifest = schemaHeader()
  manifest.add("created_at = \"" & stamp & "\"\n")
  manifest.add("format = \"directory\"\n")
  manifest.add("files = [")
  for i, fileName in StorageFiles:
    if i > 0:
      manifest.add(", ")
    manifest.add("\"" & fileName & "\"")
    copyStorageFile(configPath(fileName), result / fileName)
  manifest.add("]\n")
  atomicWriteFile(result / "manifest.toml", manifest)

proc restoreBackup*(backupPath: string; force: bool) =
  if not dirExists(backupPath):
    raise newException(IOError, "Backup path does not exist or is not a directory: " &
        backupPath)
  let manifestPath = backupPath / "manifest.toml"
  if not fileExists(manifestPath):
    raise newException(IOError, "Backup manifest missing: " & manifestPath)
  discard readConfig(manifestPath)

  let root = dataRoot()
  if not force:
    for fileName in StorageFiles:
      let target = root / fileName
      if fileExists(target):
        raise newException(IOError,
            "Refusing to overwrite existing data file without --force: " & target)

  for fileName in StorageFiles:
    let src = backupPath / fileName
    if not fileExists(src):
      raise newException(IOError, "Backup file missing: " & src)
    discard readConfig(src)
    copyStorageFile(src, root / fileName)
