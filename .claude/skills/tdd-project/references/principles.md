# Keeping a test-first loop fast

The kit exists because of one measurement. A project's check took nine minutes and
its test stage 523 seconds, of which only 60 were CPU time: the tests were waiting
on the real clock. Running them in simulated time took 23 seconds; splitting them
over four processes, 10; a content-keyed pass cache made repeat checks free. Nothing
was skipped and no test was weakened. The order below is the order that paid off.

## Contents
1. Finding the time
2. Remove waiting
3. Make runs deterministic
4. Isolate, then parallelise
5. Tier by cost
6. When the pass cache is sound
7. Subagents
8. What not to do

## 1. Finding the time

Measure before changing anything. For each stage compare wall time with CPU time
(`tools/check.py` does this and prints `note: ... this stage mostly waits`; by hand,
`time <command>` shows `real` against `user` + `sys`).

- Wall much larger than CPU: the suite is waiting. Go to section 2. This is the
  common case in anything with timers, animation, physics, retries, polling, network
  calls or `sleep`.
- Wall about equal to CPU on one core: it is computing serially. Go to section 4.
- Then find the few slowest tests (most runners can list them: `pytest --durations=10`,
  `go test -json`, `cargo test -- --report-time`, a JUnit report). A handful usually
  hold most of the time.

## 2. Remove waiting

A test should take as long as its computation, not as long as the behaviour it
describes.

- **Fake the clock.** Code that needs the time takes a clock as a parameter; tests
  pass one they advance by hand. Most ecosystems have one ready: `freezegun` or
  `time-machine` (Python), `mock.timers` or `vi.useFakeTimers` (JS), paused tokio
  time (Rust), `testing/synctest` or an injected `func() time.Time` (Go),
  `TestScheduler` / virtual time (Rx, coroutines), `Clock` (Java).
- **Simulated time for simulations.** Games, physics and animation engines usually
  can step a fixed delta per frame as fast as frames compute (Godot `--fixed-fps`,
  Unity/Unreal fixed timestep with time scale, a manual `world.step(dt)` loop).
  Run tests that way and express waits in simulated frames or seconds.
- **No sleeps to wait for something.** Await the event, or poll a condition with a
  short deadline. A sleep is both slow and flaky.
- **Fake the far side.** Replace real networks and services with in-process fakes
  in unit tests; keep a few real ones for the full tier.
- **Timeouts stay real.** A per-test wall-clock timeout guards against hangs; it is
  not a way to wait.

## 3. Make runs deterministic

The same files must give the same result. Determinism is what lets a pass be
believed, a failure be reproduced, and a cached pass be reused.

- Seed every random source and pass it in.
- No dependence on the date, the locale, the time zone, map iteration order or the
  network.
- Simulated time (section 2) removes the largest source of jitter.
- A test that fails one run in fifty is a defect with a cause: find it (usually
  shared state, real time or an unawaited task) instead of retrying it.

Check it once: run the suite twice and compare the outputs.

## 4. Isolate, then parallelise

Parallel runs change which tests share a process, and in what order.

- Each test sets up and tears down its own state. Reset statics, singletons,
  environment variables and settings a test changed.
- No fixed ports, file names or database names: ask the OS for a port, use a temp
  directory, name databases per process.
- Then use the cores: the runner's own parallelism where it exists, `parallel = true`
  on independent stages, `files` + `{files}` to split a stage whose runner is serial.
- A test that passes alone and fails in the suite (or the reverse) is telling you
  about leaked state; `--jobs 1` and `--filter` help find it.

## 5. Tier by cost

- **Filter** (about a second): the one test being written. Red, then green.
- **Quick** (seconds, with a budget): compile or type check, lint, tests of plain
  logic. Run after each meaningful edit.
- **Full**: everything, once per piece of work and in CI. The only tier that
  supports the sentence "this works".

Put a test where its cost puts it, not where its importance does: an important slow
test still runs in every full check. Design moves tests toward quick: logic in plain
units with their dependencies passed in, thin edges around I/O.

## 6. When the pass cache is sound

The cache answers "these exact inputs already passed". It is right when the
fingerprint covers every input:

- every non-ignored project file (always covered);
- the toolchain and dependency set (`[cache].tools`; a committed lock file covers
  dependencies by itself);
- environment variables that change behaviour (`[cache].env`);
- and the tests are deterministic (section 3).

It stores passes only, only when no file changed during the run, and a filtered run
is answered only by the same filter. If results depend on something outside the
fingerprint, add it or fix the test; `--fresh` is for doubt about the cache, not a
habit.

## 7. Subagents

Duplicate verification is the main waste in multi-agent work: the subagent runs the
suite, returns, and the parent runs it again on identical files. The cache removes
that without asking anyone to trust a report:

- Brief every subagent that edits files to finish with the full check and to quote
  its summary and `CHECK:` lines.
- On return, run the check without `--fresh`. Identical files: `[CACHED]`, instant.
  Anything changed: a real run, which is when one is needed.
- The cache is keyed by content, so a pass in a worktree counts in the main checkout
  once the files match.
- Agents editing one checkout at the same time invalidate each other's passes (and
  can read each other's half-written files). Give each a worktree, or have them use
  `--filter` and `--tier quick` and run the full check once yourself.

## 8. What not to do

- Do not skip, delete or loosen tests to make the check faster or green.
- Do not select tests by guessing which code a change affects unless the selection
  is provably sound; a fast full check makes it unnecessary.
- Do not report success from a quick or filtered run.
- Do not let generated files drift untracked and unignored: they defeat the cache.
