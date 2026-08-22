type
  EmbeddedTemplateFile* = object
    group*: string
    path*: string
    content*: string

const EmbeddedTemplateFiles*: array[50, EmbeddedTemplateFile] = [
  EmbeddedTemplateFile(
    group: "common",
    path: ".envrc",
    content: staticRead("../templates/common/.envrc")
  ),
  EmbeddedTemplateFile(
    group: "common",
    path: "flake.nix",
    content: staticRead("../templates/common/flake.nix")
  ),
  EmbeddedTemplateFile(
    group: "common",
    path: ".gitignore",
    content: staticRead("../templates/common/.gitignore")
  ),
  EmbeddedTemplateFile(
    group: "common",
    path: "PROJECT",
    content: staticRead("../templates/common/PROJECT")
  ),
  EmbeddedTemplateFile(
    group: "common",
    path: "README.md",
    content: staticRead("../templates/common/README.md")
  ),
  EmbeddedTemplateFile(
    group: "go",
    path: ".github/workflows/release.yml",
    content: staticRead("../templates/go/.github/workflows/release.yml")
  ),
  EmbeddedTemplateFile(
    group: "go",
    path: ".github/workflows/tests.yml",
    content: staticRead("../templates/go/.github/workflows/tests.yml")
  ),
  EmbeddedTemplateFile(
    group: "go",
    path: "go.mod",
    content: staticRead("../templates/go/go.mod")
  ),
  EmbeddedTemplateFile(
    group: "go",
    path: "Makefile",
    content: staticRead("../templates/go/Makefile")
  ),
  EmbeddedTemplateFile(
    group: "go",
    path: "src/cmd/root.go",
    content: staticRead("../templates/go/src/cmd/root.go")
  ),
  EmbeddedTemplateFile(
    group: "go",
    path: "src/cmd/root_test.go",
    content: staticRead("../templates/go/src/cmd/root_test.go")
  ),
  EmbeddedTemplateFile(
    group: "go",
    path: "src/main.go",
    content: staticRead("../templates/go/src/main.go")
  ),
  EmbeddedTemplateFile(
    group: "nim",
    path: ".github/workflows/release.yml",
    content: staticRead("../templates/nim/.github/workflows/release.yml")
  ),
  EmbeddedTemplateFile(
    group: "nim",
    path: ".github/workflows/tests.yml",
    content: staticRead("../templates/nim/.github/workflows/tests.yml")
  ),
  EmbeddedTemplateFile(
    group: "nim",
    path: "Makefile",
    content: staticRead("../templates/nim/Makefile")
  ),
  EmbeddedTemplateFile(
    group: "nim",
    path: "{{snake_name}}.nimble",
    content: staticRead("../templates/nim/{{snake_name}}.nimble")
  ),
  EmbeddedTemplateFile(
    group: "nim",
    path: "src/{{snake_name}}.nim",
    content: staticRead("../templates/nim/src/{{snake_name}}.nim")
  ),
  EmbeddedTemplateFile(
    group: "nim",
    path: "tests/test_cli.nim",
    content: staticRead("../templates/nim/tests/test_cli.nim")
  ),
  EmbeddedTemplateFile(
    group: "rust",
    path: ".github/workflows/release.yml",
    content: staticRead("../templates/rust/.github/workflows/release.yml")
  ),
  EmbeddedTemplateFile(
    group: "rust",
    path: ".github/workflows/tests.yml",
    content: staticRead("../templates/rust/.github/workflows/tests.yml")
  ),
  EmbeddedTemplateFile(
    group: "rust",
    path: "Cargo.toml",
    content: staticRead("../templates/rust/Cargo.toml")
  ),
  EmbeddedTemplateFile(
    group: "rust",
    path: "Makefile",
    content: staticRead("../templates/rust/Makefile")
  ),
  EmbeddedTemplateFile(
    group: "rust",
    path: "examples/main.rs",
    content: staticRead("../templates/rust/examples/main.rs")
  ),
  EmbeddedTemplateFile(
    group: "rust",
    path: "src/lib.rs",
    content: staticRead("../templates/rust/src/lib.rs")
  ),
  EmbeddedTemplateFile(
    group: "cpp",
    path: ".clang-format",
    content: staticRead("../templates/cpp/.clang-format")
  ),
  EmbeddedTemplateFile(
    group: "cpp",
    path: ".github/workflows/release.yml",
    content: staticRead("../templates/cpp/.github/workflows/release.yml")
  ),
  EmbeddedTemplateFile(
    group: "cpp",
    path: ".github/workflows/tests.yml",
    content: staticRead("../templates/cpp/.github/workflows/tests.yml")
  ),
  EmbeddedTemplateFile(
    group: "cpp",
    path: "CMakeLists.txt",
    content: staticRead("../templates/cpp/CMakeLists.txt")
  ),
  EmbeddedTemplateFile(
    group: "cpp",
    path: "Makefile",
    content: staticRead("../templates/cpp/Makefile")
  ),
  EmbeddedTemplateFile(
    group: "cpp",
    path: "include/{{snake_name}}/{{snake_name}}.hpp",
    content: staticRead(
      "../templates/cpp/include/{{snake_name}}/{{snake_name}}.hpp")
  ),
  EmbeddedTemplateFile(
    group: "cpp",
    path: "src/{{snake_name}}/{{snake_name}}.cpp",
    content: staticRead("../templates/cpp/src/{{snake_name}}/{{snake_name}}.cpp")
  ),
  EmbeddedTemplateFile(
    group: "cpp",
    path: "test/basic_test.cpp",
    content: staticRead("../templates/cpp/test/basic_test.cpp")
  ),
  EmbeddedTemplateFile(
    group: "python",
    path: "base/.github/workflows/release.yml",
    content: staticRead(
      "../templates/python/base/.github/workflows/release.yml")
  ),
  EmbeddedTemplateFile(
    group: "python",
    path: "base/.github/workflows/tests.yml",
    content: staticRead("../templates/python/base/.github/workflows/tests.yml")
  ),
  EmbeddedTemplateFile(
    group: "python",
    path: "base/README.md",
    content: staticRead("../templates/python/base/README.md")
  ),
  EmbeddedTemplateFile(
    group: "python",
    path: "base/pyproject.toml",
    content: staticRead("../templates/python/base/pyproject.toml")
  ),
  EmbeddedTemplateFile(
    group: "python",
    path: "base/src/{{snake_name}}/__init__.py",
    content: staticRead(
      "../templates/python/base/src/{{snake_name}}/__init__.py")
  ),
  EmbeddedTemplateFile(
    group: "python",
    path: "base/src/{{snake_name}}/__main__.py",
    content: staticRead(
      "../templates/python/base/src/{{snake_name}}/__main__.py")
  ),
  EmbeddedTemplateFile(
    group: "python",
    path: "base/tests/test_cli.py",
    content: staticRead("../templates/python/base/tests/test_cli.py")
  ),
  EmbeddedTemplateFile(
    group: "python",
    path: "flavours/nix/Makefile",
    content: staticRead("../templates/python/flavours/nix/Makefile")
  ),
  EmbeddedTemplateFile(
    group: "python",
    path: "flavours/uv/Makefile",
    content: staticRead("../templates/python/flavours/uv/Makefile")
  ),
  EmbeddedTemplateFile(
    group: "python",
    path: "flavours/pixi/Makefile",
    content: staticRead("../templates/python/flavours/pixi/Makefile")
  ),
  EmbeddedTemplateFile(
    group: "python",
    path: "flavours/pixi/pixi.toml",
    content: staticRead("../templates/python/flavours/pixi/pixi.toml")
  ),
  EmbeddedTemplateFile(
    group: "python",
    path: "flavours/micromamba/Makefile",
    content: staticRead("../templates/python/flavours/micromamba/Makefile")
  ),
  EmbeddedTemplateFile(
    group: "python",
    path: "flavours/micromamba/environment.yml",
    content: staticRead(
      "../templates/python/flavours/micromamba/environment.yml")
  ),
  EmbeddedTemplateFile(
    group: "zig",
    path: ".github/workflows/release.yml",
    content: staticRead("../templates/zig/.github/workflows/release.yml")
  ),
  EmbeddedTemplateFile(
    group: "zig",
    path: ".github/workflows/tests.yml",
    content: staticRead("../templates/zig/.github/workflows/tests.yml")
  ),
  EmbeddedTemplateFile(
    group: "zig",
    path: "Makefile",
    content: staticRead("../templates/zig/Makefile")
  ),
  EmbeddedTemplateFile(
    group: "zig",
    path: "build.zig",
    content: staticRead("../templates/zig/build.zig")
  ),
  EmbeddedTemplateFile(
    group: "zig",
    path: "src/main.zig",
    content: staticRead("../templates/zig/src/main.zig")
  )
]
