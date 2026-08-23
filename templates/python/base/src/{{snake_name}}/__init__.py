"""{{PROJECT_NAME}} package."""

from importlib.metadata import PackageNotFoundError
from importlib.metadata import version as _installed_version
from pathlib import Path

__all__ = ["__version__", "name"]


def _read_version() -> str:
    """The version: from package metadata when installed, from PROJECT when run from a checkout."""
    try:
        return _installed_version("{{kebab_name}}")
    except PackageNotFoundError:
        pass
    for parent in Path(__file__).resolve().parents:
        project = parent / "PROJECT"
        if project.is_file():
            fields = [
                line.strip()
                for line in project.read_text().splitlines()
                if line.strip() and not line.startswith("#")
            ]
            if len(fields) >= 2:
                return fields[1]
    return "0.0.0+unknown"


__version__ = _read_version()


def name() -> str:
    """Return the project display name."""
    return "{{PROJECT_NAME}}"
