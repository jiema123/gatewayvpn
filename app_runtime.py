#!/usr/bin/env python3
from __future__ import annotations

import os
import sys
from pathlib import Path


def is_frozen_app() -> bool:
    return bool(getattr(sys, "frozen", False))


def app_root_dir() -> Path:
    if is_frozen_app():
        exe_dir = Path(sys.executable).resolve().parent
        if exe_dir.name == "bin":
            return exe_dir.parent
        return exe_dir
    return Path(__file__).resolve().parent


def data_dir() -> Path:
    env_dir = os.environ.get("VPNGATE_DATA_DIR")
    if env_dir:
        return Path(env_dir).resolve()
    return app_root_dir() / "vpngate_data"
