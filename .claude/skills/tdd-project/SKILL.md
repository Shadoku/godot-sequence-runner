---
name: tdd-project
description: Scaffold a new software project in any language (or adopt an existing one) with a test-first workflow that stays fast - one check command with a quick tier and a full tier, single-test filtering, parallel stages, a content-keyed pass cache so verified work is never re-tested (including work returned by subagents), and a CLAUDE.md that teaches the loop. Use this whenever the user starts or scaffolds a new project, repo, library, CLI, service or app, asks to "set up tests", "set up TDD", "add CI", "add a check script" or "make this project AI-friendly / verifiable", complains that tests or the AI's test runs are slow or duplicated, or invokes /tdd-project by name - even if they never say "TDD". For Godot game projects use the godot-project skill instead.
---

# Test-first project kit (any language)

This skill gives a project one command that says whether it works:

```
python3 tools/check.py        # ends with CHECK: PASS or CHECK: FAIL (<stages>)
```

`tools/check.py` knows nothing about the language. It runs the stages listed in
`check.toml` (build, lint, unit tests, integration tests, anything with an exit code)
and adds what keeps a test-first loop fast enough to actually be followed:

- **Tiers**: `--filter <name>` (one test) for red/green, `--tier quick` (seconds) while
  implementing, the full check once before reporting done.
- **Pass cache**: a pass is remembered by a fingerprint of the project's files and
  toolchain; the same files checked again answer `[CACHED]` instantly. This is what
  makes re-checking a subagent's returned work free, without trusting its word.
- **Parallel stages**, and splitting a test stage over processes by file.
- **A waiting detector**: a stage that takes long but uses little CPU is flagged,
  because real-time waits are usually the largest and cheapest thing to remove.

Why this matters: a check that takes minutes gets skipped, batched or argued around,
and then test-first development quietly stops. The kit's job is to keep the honest
path the fast path.

## Decide which mode applies

| Situation | Do |
|---|---|
| Empty or missing directory, or the user asks for a new project | **Scaffold** |
| A project exists but has no `tools/check.py` + `check.toml` | **Adopt** |
| Both exist | **Develop** with the loop |

Check with `ls tools/check.py check.toml` first.

## Scaffold a new project

1. Settle the inputs, defaulting rather than asking when the user did not say: the
   target directory, a display name, and the language. Presets exist for `python`,
   `node`, `rust` and `go`; anything else is `generic` (step 4).
2. Run the scaffolder from this skill's directory:
   ```
   python3 <skill-dir>/scripts/new_project.py <target> --lang <preset> --name "Name"
   ```
   It writes `tools/check.py`, `check.toml`, `CLAUDE.md`, `.gitignore`, a CI workflow,
   a small worked example (a `Counter` with a unit and an integration test), copies
   this skill into `<target>/.claude/skills/` so later sessions have it, and runs
   `git init` when the target is not in a repository.
3. Run `python3 tools/check.py` in the project. It must end with `CHECK: PASS` before
   you report success. If the first pass prints `note: this pass was not stored ...
   files changed while the check ran`, the check generated a file: commit it if it is
   a lock file, otherwise add it to `.gitignore`, and run again. A second run on
   unchanged files must print `[CACHED]`; if it does not, the cache is not working
   and the note says why.
4. For `generic` (no preset): the scaffolded `check.toml` fails on purpose until its
   three placeholder stages are real commands. Fill them in for the project's
   toolchain, following `references/check-toml.md`, and fill the "Writing tests" and
   "Layout" placeholders in `CLAUDE.md`. Create a first unit test so the stages have
   something to run.
5. Adjust `CLAUDE.md`'s Layout section to the real files, and replace the `Counter`
   example with the user's first feature when they describe one (test first).

Requirements: Python 3.11+ to run `check.py` (any project language), and git for the
pass cache to see exactly the non-ignored files.

## Adopt the kit into an existing project

```
python3 <skill-dir>/scripts/new_project.py <project-dir> --adopt [--lang <preset>]
```

This writes only missing files and never touches sources; the language is detected
from marker files (`Cargo.toml`, `go.mod`, `package.json`, `pyproject.toml`) when not
given. Then:

1. Rewrite `check.toml`'s stages to the commands the project really uses (look at
   its CI config, Makefile, package scripts and README before inventing any).
2. Run the full check. Report pre-existing failures to the user rather than quietly
   fixing unrelated code.
3. Look at the times. Read `references/principles.md` ("Finding the time") and act on
   what the report shows: split tests into quick and full, and chase any stage
   flagged as mostly waiting.
4. If a `CLAUDE.md` already exists, merge the Commands, development loop, "How the
   check stays fast" and Subagents sections from `assets/template/CLAUDE.md` into it.

## Develop with the loop

The scaffolded `CLAUDE.md` carries the working rules; in short:

1. Write or adjust a test first and watch it fail for the right reason:
   `python3 tools/check.py --filter <name>`.
2. Implement, re-running `--filter` and `--tier quick`. Not the full check after
   every edit.
3. Run `python3 tools/check.py` once when done; fix until `CHECK: PASS`; report with
   the test stages' summary lines quoted.
4. Brief subagents to finish with the full check. When their work returns, run the
   check yourself without `--fresh`: unchanged files answer from the cache, changed
   files run for real. That replaces both blind trust and blind re-running.

When the check gets slow, treat it as a defect and fix it with
`references/principles.md`, in its order: measure, remove waiting, make runs
deterministic, parallelise, then tier. Do not reach for skipping tests.

## Reference files

- `references/check-toml.md`: every `check.toml` key with examples, how to add a
  stage (lint, types, build, end-to-end), splitting by file, the pass cache's
  `[cache]` settings, and recipes for toolchains without a preset. Read when writing
  or changing `check.toml`.
- `references/principles.md`: why the kit is built this way and how to keep a suite
  fast: finding where the time goes, fake clocks and simulated time, determinism and
  isolation, what belongs in which tier, when the cache is sound, working with
  subagents. Read when a check is slow or flaky, or when adopting a project.

## Bundled files

- `scripts/new_project.py`: the scaffolder (new project or `--adopt`).
- `assets/template/`: `tools/check.py`, the `CLAUDE.md` template, CI and `.gitignore`.
- `assets/presets/<lang>/`: `check.toml`, the worked example, and the language's
  testing notes for `CLAUDE.md`.

When you improve `tools/check.py` inside a project, port the change back to
`assets/template/tools/check.py` so the next project gets it.
