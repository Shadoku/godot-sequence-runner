# Sequence Runner (Godot 4.7)

A Godot 4 addon in one file, `sequence_runner.gd`: XML command sequences compiled to
callables and run as a coroutine. `README.md` is its documentation. Other projects
copy or mirror that one file, so it stays at the repository root and stays
self-contained (no second script, no autoload, no project setting).

Every change to this project is verified by `python3 tools/check.py`, which runs the
stages listed in `check.toml`. Trust its output over your own reasoning about whether
code works.

## Commands

| What | Command |
|---|---|
| Everything | `python3 tools/check.py` |
| Quick tier (the fast stages; the inner loop) | `python3 tools/check.py --tier quick` |
| One test or test file | `python3 tools/check.py --filter <name>` |
| One stage | `python3 tools/check.py --only <stage>` |
| A stage's full output | `python3 tools/check.py --only <stage> --verbose` |
| Run again although these exact files already passed | `python3 tools/check.py --fresh` |
| The stages and their tiers | `python3 tools/check.py --list` |

## The development loop

1. Before changing behaviour, write or adjust a test that describes the intended
   behaviour. Run it alone (`--filter <name>`) and watch it fail for the right reason: a
   test that has never failed has not shown that it can.
2. Implement the change, re-running that test (`--filter`) and `--tier quick`. Do not
   run the full check after every edit.
3. When the work is done, run `python3 tools/check.py` once. Read the output from the
   top: the first failing stage usually explains the rest.
4. Fix and re-run until the last line is `CHECK: PASS`.
5. Only then report done, quoting the test stages' summary lines.

Never say a change works without a passing full check (`--tier quick` and `--filter`
runs do not count). If the check cannot run here (a missing toolchain, no network), say
so explicitly instead of guessing.

## How the check stays fast

A check that takes minutes gets skipped or run rarely, and then it protects nothing.
These are the rules that keep it at seconds:

- **Tiers.** `--filter` (one test, about a second) for red and green; `--tier quick`
  (seconds; budget in `check.toml`) while implementing; the full check once, before
  reporting done. CI always runs the full check. A test belongs in the quick tier only
  if it touches no process, network, service, real clock or large file.
- **No waiting.** Tests must not sleep or wait on the real clock, a real network or a
  real service where a fake one will do: pass the clock, the random source and the
  services into the code and hand tests fake ones. The check flags a stage that takes
  long while using little CPU (`note: ... this stage mostly waits`): fix that first, it
  is usually worth more than any other speed-up.
- **Deterministic.** The same files must give the same result: seed randomness, fake
  time, and do not depend on test order or on state another test left behind (reset
  globals in teardown). A flaky test makes every pass doubtful and the pass cache unsafe.
- **Parallel.** Stages marked `parallel` run side by side, and a stage with `files` is
  split over processes by file. Tests therefore must not share ports, fixed temp paths
  or other machine-wide state: use an OS-assigned port and a fresh temp directory.
- **Pass cache.** A passing run stores a fingerprint of every project file (tracked or
  untracked, not ignored) and of the toolchain under `~/.cache/check-pass/`. Running the
  check again on exactly the same files prints `[CACHED]`, the stored report and
  `CHECK: PASS` without running anything; one changed byte and it runs for real.
  Failures are never cached. `--fresh` ignores the cache: use it only when you doubt the
  cache itself (something outside the project changed that `check.toml`'s `[cache]` does
  not name, and then add it there), not to double-check.

### Subagents

- A subagent that changes files finishes with `python3 tools/check.py` and reports the
  summary and `CHECK:` lines; tell it so in its brief. While it works it uses `--filter`
  and `--tier quick` like anyone else.
- When its work comes back, run `python3 tools/check.py` yourself, without `--fresh`. If
  the files are what the subagent verified, the answer comes from the cache at once; if
  anything changed since (your own edits, a merge, another agent's work), the check runs
  for real, which is exactly when it is needed. Do not re-run tests "to be sure" in any
  other way.
- The cache is keyed by content, not by directory, so a subagent's pass in a worktree
  answers for the main checkout once it holds the same files.
- Several subagents editing the same checkout at once invalidate each other's runs (a
  pass is stored only if no file changed while the check ran): give them worktrees, or
  have them use `--filter` / `--tier quick` and run the full check once yourself.

## Reading the report

| Output | Meaning | What to do |
|---|---|---|
| `[FAIL] <stage> (..., exit N)` + output | the stage's command failed; the last lines of its output follow | read them; `--only <stage> --verbose` shows all of it |
| `[FAIL] <stage> (..., timed out after Ns)` | the command hung or is too slow | find what it waits for; raise `timeout` in `check.toml` only for a real reason |
| `[SKIP] <stage> (<other> failed)` | an earlier stage marked `stop_on_fail` failed | fix that one first |
| `[SKIP] <stage> (not installed: tool)` | an optional tool is missing here | fine locally; the pass is not a full one, so CI should have the tool |
| `[NONE] <stage>: no test matches --filter=...` | that stage has no such test | fine if another stage matched; if none did the check fails: check the name |
| `[CACHED] these exact files passed ...` | nothing ran: the same files already passed | nothing; it is a pass. `--fresh` runs it again |
| `note: ... this stage mostly waits` | long wall time, little CPU | remove sleeps, fake the clock or the service |
| `note: the quick tier took ...; its budget is ...` | the inner loop is getting slow | move slow tests to the full tier or make them faster |
| `note: this pass was not stored ...: files changed while the check ran (...)` | the check writes files that are neither ignored nor committed | add them to `.gitignore`, or commit them if they belong to the project |
| a test passes alone (`--filter`) but fails in the full run, or the other way round | it depends on order or on shared state | make it set up and reset its own state; `--jobs 1` runs one command at a time |

## Writing tests

- The tests are a Godot project of their own, `tests/`. Every stage runs Godot
  headless on it through `tools/godot.py`, which first copies `sequence_runner.gd`
  into `tests/addons/sequence_runner/` (ignored by git). Inside Godot, `res://` is
  `tests/`. A fixture is `res://fixtures/sequences/x.xml`.
- Files: `tests/unit/**/test_*.gd`, `extends TestCase`, methods named `test_*`.
- A fresh instance runs per test method: `before_each` / `after_each` for fixtures.
- Assertions: `assert_eq`, `assert_ne`, `assert_true`, `assert_false`, `assert_null`,
  `assert_not_null`, `assert_almost_eq`, `assert_gt`, `assert_lt`, `assert_has`,
  `fail`, `skip`.
- Tests are Nodes in the tree: `add_child(node)`; children are freed automatically.
  `await wait_frames(n)`, `await wait_seconds(s)`, `await await_signal(sig, timeout)`
  for async behaviour. Keep waits in fixtures at a few hundredths of a second.
- Any `ERROR` / `SCRIPT ERROR` printed while a test runs fails it. Set
  `allow_errors = true` in a test that triggers one on purpose (the runner reports
  every problem with `push_error`).
- One fixture per feature: `tests/fixtures/sequences/` (every file there validates)
  and `tests/fixtures/broken_sequences/` (compile problems on purpose).
- One test: `python3 tools/check.py --filter <name>` (a substring of
  `unit/test_x.gd::test_y`). A name that matches nothing fails.
- Randomness: give the runner a seeded `rng`; never assert on the global generator.
- Godot is `$GODOT`, then `godot` on PATH, then `~/.cache/godot/<version>/godot`,
  which `bash tools/install_godot.sh` downloads (the version is in `.godot-version`;
  the session hook and CI both run it).

## Compatibility

Projects in use copy this file, and some subclass it. A change must not break them:

- Do not change an existing signature, default, signal or its timing, or what an
  existing command or attribute does. New behaviour is a new method, a new command,
  a new attribute, or an export whose default is the old behaviour.
- `tests/unit/test_sequence_runner.gd` pins what exists. Add tests for a new
  feature; change an existing test only when the behaviour it pins is changed on
  purpose, and say so in the commit and the README.
- A subclass registers its commands after `super.register_commands()`, so its
  command wins over a built-in of the same name. Its methods cannot: a new method or
  member here whose name a subclass already uses stops that subclass from compiling.
  Choose distinctive names (a known subclass has a static `play()`), and list every
  new public name in the README.
- `start()` called while a sequence runs hands over to the new one (the README's
  "Chain into another sequence"). Keep it.
- The file must stay usable alone: everything it needs is inside it.

## Design for testability

- Put rules and state in plain units (functions, classes, modules) that need no file,
  network, UI, framework or clock. They test in milliseconds and belong in the quick tier.
- Keep the edges thin: code that reads input, talks to a service or draws something
  should call the plain units and do little else, so the slow tier has little to cover.
- Pass dependencies in (clock, randomness, storage, network client) instead of reaching
  for globals; a test then hands in a fake.
- When behaviour is hard to test, treat that as a design finding and change the design
  before writing a slow or brittle test around it.

## Layout

```
check.toml             the check's stages, tiers, budget and cache settings
tools/check.py         the one command to verify the project (language-agnostic; reads check.toml)
sequence_runner.gd     the addon: the whole of it, the one file other projects copy
README.md              the addon's documentation: every command, attribute and public method
docs/card-game-additions-plan.md  the agreed plan of additions (steps, design, compatibility rules) and its status
tools/godot.py         runs Godot headless on tests/ after copying the addon into it; finds the binary
tools/install_godot.sh downloads the Godot pinned in .godot-version into ~/.cache/godot/
.godot-version         the pinned Godot release
tests/project.godot    the test project (keeps Godot from scanning tests/ inside another project)
tests/framework/       the test runner (runner.gd) and TestCase (test_case.gd)
tests/tools/validate_scripts.gd  compiles every script of the test project (the validate stage)
tests/unit/            the tests; test_sequence_runner.gd is the regression suite
tests/fixtures/        the XML sequences the tests run
.claude/hooks/session-start.sh  cloud sessions: installs Godot and warms the import cache
.claude/skills/tdd-project/     the skill this setup came from
.github/workflows/ci.yml    runs the full check on push and pull request
```

Keep this list current when files are added, moved or change purpose.

## Conventions

- A new stage (a linter, a type checker, a build, an end-to-end run) is added to
  `check.toml`, not run by hand: what is not in the check is not verified.
- Generated files and caches go in `.gitignore`; lock files are committed.
- GDScript: tabs, static types on every declaration, `## doc comments` on exported
  properties and public methods.
- Commit `*.uid` sidecar files; never commit `tests/.godot/` or `tests/addons/`.
- A feature is one commit: the test, the change to `sequence_runner.gd` and its
  README section together.
- Never weaken a test, skip it or raise a tolerance to get a pass; if a test is wrong,
  say why and fix the test in the open.
