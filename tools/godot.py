#!/usr/bin/env python3
"""Run Godot headless on the test project (tests/), for check.toml's stages.

  python3 tools/godot.py <godot arguments>

The addon is the single file sequence_runner.gd at the repository root, so that a
project can copy or mirror it alone. The test project lives in tests/ (its own
project.godot keeps Godot from scanning it when the whole repository sits inside
another project), and this script copies the addon into
tests/addons/sequence_runner/ (ignored by git) before starting Godot, so the tests
always run the file as it is now.

Godot is $GODOT, then `godot` on PATH, then ~/.cache/godot/<version>/godot, which
tools/install_godot.sh downloads (<version> is in .godot-version).
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "tests"
ADDON = "sequence_runner.gd"


def godot_version() -> str:
    return (ROOT / ".godot-version").read_text().strip()


def find_godot() -> str:
    candidates = []
    if os.environ.get("GODOT"):
        candidates.append(os.environ["GODOT"])
    for name in ("godot", "godot4", "godot4-stable"):
        found = shutil.which(name)
        if found:
            candidates.append(found)
    candidates.append(str(Path.home() / ".cache" / "godot" / godot_version() / "godot"))
    for candidate in candidates:
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    sys.exit("No Godot binary found. Set GODOT=/path/to/godot, put `godot` on PATH, or run "
             "`bash tools/install_godot.sh` to download " + godot_version() + ".")


def sync_addon() -> None:
    """Copy the addon into the test project when the copy is missing or differs."""
    source = ROOT / ADDON
    target = PROJECT / "addons" / "sequence_runner" / ADDON
    if target.exists() and target.read_bytes() == source.read_bytes():
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)


def main() -> int:
    if sys.argv[1:] == ["--version"]:
        return subprocess.run([find_godot(), "--version"]).returncode
    sync_addon()
    return subprocess.run([find_godot(), "--headless", "--path", str(PROJECT), *sys.argv[1:]], cwd=ROOT).returncode


if __name__ == "__main__":
    sys.exit(main())
