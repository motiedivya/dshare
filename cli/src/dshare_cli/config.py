"""Cross-platform config storage for the dshare CLI.

No third-party dependency (e.g. platformdirs) is used on purpose: the CLI
should install with nothing but `requests`, so the config directory logic
is a small, explicit branch on `sys.platform`.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

_ENV_SERVER = "DSHARE_SERVER"
_CONFIG_FILENAME = "config.json"
DEFAULT_SERVER = "https://dshare.me"


def config_dir() -> Path:
    if sys.platform == "win32":
        base = os.environ.get("APPDATA")
        root = Path(base) if base else Path.home() / "AppData" / "Roaming"
        return root / "dshare"
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "dshare"
    xdg = os.environ.get("XDG_CONFIG_HOME")
    root = Path(xdg) if xdg else Path.home() / ".config"
    return root / "dshare"


def config_path() -> Path:
    return config_dir() / _CONFIG_FILENAME


def load_config() -> dict:
    path = config_path()
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def save_config(data: dict) -> None:
    directory = config_dir()
    directory.mkdir(parents=True, exist_ok=True)
    path = config_path()
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def get_server(explicit: str | None = None) -> str:
    """Resolve the server URL: --server flag > env var > saved config > default."""
    if explicit:
        return explicit.rstrip("/")
    env = os.environ.get(_ENV_SERVER)
    if env:
        return env.rstrip("/")
    saved = load_config().get("server")
    if saved:
        return str(saved).rstrip("/")
    return DEFAULT_SERVER


def set_server(url: str) -> Path:
    config = load_config()
    config["server"] = url.rstrip("/")
    save_config(config)
    return config_path()
