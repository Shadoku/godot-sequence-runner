# {{NAME}}

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

{{TESTING}}

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
{{LAYOUT}}
.github/workflows/ci.yml    runs the full check on push and pull request
```

Keep this list current when files are added, moved or change purpose.

## Conventions

- A new stage (a linter, a type checker, a build, an end-to-end run) is added to
  `check.toml`, not run by hand: what is not in the check is not verified.
- Generated files and caches go in `.gitignore`; lock files are committed.
- Never weaken a test, skip it or raise a tolerance to get a pass; if a test is wrong,
  say why and fix the test in the open.
