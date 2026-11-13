#!/usr/bin/env python3
"""Scaffold a project with a tiered, cached, test-first check (tools/check.py + check.toml).

  New project:
    python3 new_project.py ~/code/my_tool --lang python --name "My Tool"

  Adopt an existing project (adds the check; never touches its sources):
    python3 new_project.py ~/code/existing --adopt --lang rust

Options:
  --lang L        python | node | rust | go | generic (default: detected from the target's
                  files, else generic). `generic` writes a check.toml to fill in by hand.
  --name NAME     display name (default: the target folder's name)
  --adopt         add the tooling to an existing project: only missing files are written,
                  the example code is left out
  --force         overwrite files that exist
  --no-examples   leave out the example code and tests
  --no-ci         no .github/workflows/ci.yml
  --no-skill      do not copy this skill into <target>/.claude/skills/
  --no-git        do not run `git init` when the target is not in a repository
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent
TEMPLATE = SKILL_DIR / "assets" / "template"
PRESETS = SKILL_DIR / "assets" / "presets"
# The first marker file found in the target picks the preset.
MARKERS = [("Cargo.toml", "rust"), ("go.mod", "go"), ("package.json", "node"),
           ("pyproject.toml", "python"), ("setup.py", "python"), ("requirements.txt", "python")]


def detect_lang(target: Path) -> str:
    for marker, lang in MARKERS:
        if (target / marker).exists():
            return lang
    return "generic"


def slug_of(name: str) -> str:
    """A name usable as a package, crate and module name: lower_snake_case, a letter first."""
    slug = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_") or "project"
    return slug if slug[0].isalpha() else "p_" + slug


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("target")
    ap.add_argument("--lang", choices=sorted(p.name for p in PRESETS.iterdir() if p.is_dir()))
    ap.add_argument("--name")
    ap.add_argument("--adopt", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--no-examples", action="store_true")
    ap.add_argument("--no-ci", action="store_true")
    ap.add_argument("--no-skill", action="store_true")
    ap.add_argument("--no-git", action="store_true")
    args = ap.parse_args()

    target = Path(args.target).expanduser().resolve()
    existing = target.exists() and any(p.name != ".git" for p in target.iterdir())
    if existing and not (args.adopt or args.force):
        sys.exit(f"{target} is not empty. Use --adopt to add the check to an existing project "
                 "(only missing files are written), or --force to overwrite.")
    target.mkdir(parents=True, exist_ok=True)
    lang = args.lang or detect_lang(target)
    preset = PRESETS / lang
    name = args.name or target.name
    values = {"{{NAME}}": name, "{{SLUG}}": slug_of(name)}

    def fill(text: str) -> str:
        for key, value in values.items():
            text = text.replace(key, value)
        return text

    written: list[str] = []
    kept: list[str] = []

    def write(rel: str, text: str, executable: bool = False) -> None:
        dest = target / rel
        if dest.exists() and not args.force:
            kept.append(rel)
            return
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(text)
        if executable:
            dest.chmod(0o755)
        written.append(rel)

    # The check itself and its configuration.
    write("tools/check.py", (TEMPLATE / "tools" / "check.py").read_text(), executable=True)
    write("check.toml", fill((preset / "check.toml").read_text()))

    # CLAUDE.md, with the preset's testing notes and layout lines.
    values["{{TESTING}}"] = (preset / "testing.md").read_text().strip()
    values["{{LAYOUT}}"] = (preset / "layout.md").read_text().strip()
    write("CLAUDE.md", fill((TEMPLATE / "CLAUDE.md").read_text()))

    # .gitignore: the lines that are missing are appended, in adopt mode too.
    wanted = (TEMPLATE / "gitignore").read_text() + "\n" + (preset / "gitignore").read_text()
    ignore = target / ".gitignore"
    have = ignore.read_text() if ignore.exists() else ""
    present = {line.strip() for line in have.splitlines()}
    block: list[str] = []
    for line in wanted.splitlines():
        if not line.strip() or line.startswith("#"):
            block.append(line)
        elif line.strip() not in present:
            block.append(line)
            present.add(line.strip())
    if any(l.strip() and not l.startswith("#") for l in block):
        text = "\n".join(block).strip() + "\n"
        ignore.write_text((have.rstrip() + "\n\n" if have.strip() else "") + text)
        written.append(".gitignore")

    if not args.no_ci:
        values["{{CI_SETUP}}"] = (preset / "ci-setup.yml").read_text().rstrip("\n") + "\n"
        write(".github/workflows/ci.yml", fill((TEMPLATE / "ci.yml").read_text()))

    # The worked example: only in a new project.
    files = preset / "files"
    if files.is_dir() and not args.adopt and not args.no_examples:
        for src in sorted(p for p in files.rglob("*") if p.is_file()):
            write(src.relative_to(files).as_posix(), fill(src.read_text()))

    if not args.no_skill:
        dest = target / ".claude" / "skills" / SKILL_DIR.name
        if dest.resolve() != SKILL_DIR.resolve() and (not dest.exists() or args.force):
            shutil.copytree(SKILL_DIR, dest, dirs_exist_ok=True,
                            ignore=shutil.ignore_patterns("__pycache__", "*-workspace", "results"))
            written.append(f".claude/skills/{SKILL_DIR.name}/")

    inside_repo = subprocess.run(["git", "rev-parse", "--is-inside-work-tree"], cwd=target,
                                 capture_output=True).returncode == 0
    if not inside_repo and not args.no_git and shutil.which("git"):
        subprocess.run(["git", "init", "-q"], cwd=target, check=False)
        written.append(".git/ (git init)")

    print(f"{'Adopted' if args.adopt else 'Scaffolded'} {name} ({lang}) in {target}")
    for rel in written:
        print(f"  wrote  {rel}")
    for rel in kept:
        print(f"  kept   {rel} (exists; --force overwrites)")
    print()
    if lang == "generic" or args.adopt:
        print("Next: edit check.toml so that its stages are this project's real commands, then run")
    else:
        print("Next: run")
    print(f"  cd {target} && python3 tools/check.py")
    print("It must end with CHECK: PASS before the project counts as set up.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
