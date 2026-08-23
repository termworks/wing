# Changelog

## [0.7.0] - 2026-08-23

### <!-- 0 -->⛰️  Features

- Give every bundled template logic of its own
- Install templates from git, and give them logic

### <!-- 1 -->🐛 Bug Fixes

- Stop release tooling rewriting the v template version

## [0.6.0] - 2026-08-23

### <!-- 0 -->⛰️  Features

- Add a make templates recipe to sync into the config dir
- Report the built artifact from every make build
- Build c and c++ static against musl by default
- Default c and c++ to clang, add static musl builds
- Add v and d templates, default c and c++ to xmake
- Give c and c++ cmake and xmake flavours
- Drive generated projects with .make.lua and .env.lua
- Search every template root, layering common
- Add user config, placeholders and apply handlers
- Declare templates in lua, not in nim

### <!-- 1 -->🐛 Bug Fixes

- Build the zig template against zig 0.16
- Stop release tooling rewriting the nim template version
- Run the static build instead of listing the environment

### <!-- 3 -->📚 Documentation

- Document the lua config surface

### Build

- Source nim, musl and lua from the flake in CI

## [0.5.3] - 2026-08-22

### <!-- 7 -->⚙️ Miscellaneous Tasks

- Build static musl linux only, drop macos

### Build

- Make the static musl binary the default

## [0.5.2] - 2026-08-22

### <!-- 1 -->🐛 Bug Fixes

- Format every Nim source, not one level deep
- Unload a project when the next .envrc is refused
- Read the version from wing.nimble

### <!-- 2 -->🚜 Refactor

- Drop the bobabrew --path workaround

## [0.5.1] - 2026-08-22

### <!-- 0 -->⛰️  Features

- Better structure
- Transition TUI to Bobabrew
- Embed templates and expose `dp init` command
- Add built-in starter templates

### <!-- 2 -->🚜 Refactor

- Rename project to wing and restructure src

### <!-- 7 -->⚙️ Miscellaneous Tasks

- Cleanup

## [0.2.1] - 2026-06-21

## [0.2.0] - 2026-06-21

### <!-- 0 -->⛰️  Features

- Consolidate data management under `wing data`
- To NIIIIIM
- To NIIIIIM
- Add project, template, workspace, and machine commands

### Build

- Simplify devbox configuration and scripts

## [0.1.10] - 2025-04-25

### <!-- 0 -->⛰️  Features

- Refactor item selection and improve user interaction in app
- Enhance machine selection and user interaction in TUI
- Refactor machine listing command and implement table formatting

### <!-- 1 -->🐛 Bug Fixes

- Cleanup stupid staff

### <!-- 2 -->🚜 Refactor

- Machine command and help message in mod.rs and list.rs
- Refactor machine addition functionality
- Refactor code for improved readability and maintainability
- Refactor and add traits to Host and Machine structs
- Refactor machine handling and add TOML support
- Refactor code for improved readability and maintainability

### <!-- 7 -->⚙️ Miscellaneous Tasks

- Use Jammy Jellyfish in GitHub Actions
- Refactor command handling and improve environment integration
- Refactor devbox configuration for improved build process
- Refactor machine listing and table generation
- Update widget appearance in UI
- Add `regex` dependency with version `1.10.5` to `Cargo.toml`

### Build

- Refine build and script execution environment

### Refractor

- Refactor machine command and methods in Machines
- Update tabled crate and refactor handle function

## [0.1.6] - 2024-06-24

### <!-- 0 -->⛰️  Features

- Refactor machine management logic
- Handle serialization and deserialization of machines.toml
- Update dependencies and refactor machine handling
- Add `serde` dependency and refactor machine-related code
- Add 'inquire' dependency and 'list' subcommand
- Update machine commands to support interfaces
- Refactor machine-related code and add config related crates
- Refactor interactive mode interface and error handling
- Refactor interactive UI functionality with ratatui

### <!-- 2 -->🚜 Refactor

- Refactor code structure and remove unused imports and commented code

### <!-- 7 -->⚙️ Miscellaneous Tasks

- Refactor code and optimize imports in machine commands

## [0.1.5] - 2024-06-22

### <!-- 0 -->⛰️  Features

- Update machine arguments and commands

## [0.1.4] - 2024-06-22

### <!-- 7 -->⚙️ Miscellaneous Tasks

- Update TOOLCHAIN_VERSION in release workflow

## [0.1.3] - 2024-06-22

### <!-- 0 -->⛰️  Features

- Update command line interface options
- Refactor file structure and remove unused imports in arguments and commands
- Add commands for managing projects, workspaces, and templates

### <!-- 7 -->⚙️ Miscellaneous Tasks

- Update `rust-build/rust-build.action` action to `v1.4.5` in release workflow
- Update .gitignore to ignore devbox.lock file

## [0.1.1] - 2024-06-21

### <!-- 0 -->⛰️  Features

- Refactor command line argument handling and add subcommands

### <!-- 2 -->🚜 Refactor

- Remove commented out code and utilities

### <!-- 3 -->📚 Documentation

- Update wing description in README file
- Update README.md file and fix license badge

### Build

- Update build and run export aliases

<!-- BRESILLA -->
