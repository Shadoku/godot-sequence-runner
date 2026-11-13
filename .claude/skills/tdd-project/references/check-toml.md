# check.toml

`tools/check.py` runs the stages of `check.toml`, in order, from the project root.
A stage is any shell command; exit code 0 is a pass.

## Contents
1. Stage keys
2. Tiers and the budget
3. Filtering to one test
4. Running in parallel and splitting by file
5. The pass cache's settings
6. Recipes for other toolchains
7. Adding kinds of stages

## 1. Stage keys

```toml
[[stage]]
name = "unit"                       # required: the report's name for it
run = "pytest -q tests/unit"        # required: the command
tier = "quick"                      # "quick" or "full" (default)
filter = "pytest -q tests/unit -k {filter}"   # the command under --filter
no_match_exit = [5]                 # filter exit codes meaning "no test matches"
filter_match = '^=== RUN'           # or: a regex the output matches only if a test ran
summary = '^.*\d+ passed.*$'        # runner lines to show under a pass (last four)
parallel = true                     # run beside neighbouring parallel stages
stop_on_fail = true                 # skip later stages when this fails
files = "tests/int/test_*.py"       # with {files} in run: split over processes by file
max_processes = 4                   # cap for that split
env = { APP_ENV = "test" }          # extra environment
timeout = 600                       # seconds
tail = 60                           # output lines shown on failure
needs = ["docker"]                  # executables required
if_missing = "skip"                 # skip instead of fail when one is missing
```

`{filter}` is shell-quoted for you; `{jobs}` is the number of parallel jobs.
Use single-quoted TOML strings for regexes so backslashes stay literal.

## 2. Tiers and the budget

```toml
[budget]
quick = 10     # seconds; a note is printed when the tier takes longer
full = 120
```

Quick is what runs between edits, so it holds only what is fast and local: a compile
or type check, a linter, and tests of plain logic. Anything that starts a process,
touches a network, database, browser, GPU or the real clock is `full`. When the
quick tier outgrows its budget, move the slow tests out or make them faster; raising
the budget is the last resort, because a slow inner loop stops being run.

## 3. Filtering to one test

`--filter NAME` runs only stages that have a `filter` command. Runners differ in
what they do when nothing matches:

- exit with a special code (pytest and unittest: 5): list it in `no_match_exit`;
- exit 0 (go, cargo): give `filter_match`, a regex that the output matches only when
  a test actually ran;
- neither is reliable (node's built-in runner): leave both out and say so in
  CLAUDE.md's "Writing tests".

A filtered run fails when no stage matched, so a mistyped name is not a pass.

## 4. Running in parallel and splitting by file

Consecutive stages with `parallel = true` run side by side (`--jobs` at a time,
default: the CPUs). Leave it off for stages that take a shared lock or directory
(cargo's `target/`, a package install, a fixed port).

Prefer the runner's own parallelism when it has one (`pytest -n auto`, `go test`,
`cargo test`, `node --test`, `jest`). For a runner that has none, split by file:

```toml
[[stage]]
name = "integration"
files = ["tests/integration/test_*.py"]
run = "python3 -m unittest {files}"
```

The files are spread over processes of about equal work, using times remembered in
`.check/times.json` (file sizes on the first run). The times are estimates: a
process's time is shared among its files, so they sharpen over a few runs.

Parallel tests must not share machine-wide state: use OS-assigned ports
(port 0), fresh temp directories, and per-process database names.

## 5. The pass cache's settings

```toml
[cache]
enabled = true
tools = ["python3 --version", "pip freeze"]   # outputs are part of the fingerprint
env = ["DATABASE_URL"]                        # so are these variables' values
```

The fingerprint always covers every file git does not ignore (tracked or not). Add
to `tools` and `env` whatever else can change a result: compiler and interpreter
versions, the installed dependency set if it is not pinned by a committed lock file,
feature flags. If results depend on something that cannot be fingerprinted (a
shared staging server, today's date), fix the test; failing that, set
`enabled = false` rather than cache answers that may be wrong.

A pass is stored only when no file changed during the run. If the check itself
writes files (a lock file, a snapshot, a coverage report), commit them or ignore
them; the report names them.

## 6. Recipes for other toolchains

Quick stages first, then full. Adapt paths and names to the project.

**TypeScript (vitest)**
```toml
[[stage]] name = "types"  run = "npx tsc --noEmit"  tier = "quick"  stop_on_fail = true
[[stage]] name = "unit"   run = "npx vitest run tests/unit"  filter = "npx vitest run -t {filter}"  tier = "quick"
[[stage]] name = "e2e"    run = "npx playwright test --trace off"
```
(Write each as a full `[[stage]]` table; they are shortened here.)

**Java / Kotlin (Gradle)**: `./gradlew compileTestJava` (quick, stop_on_fail),
`./gradlew test --tests '*Unit*'` or a `unitTest` task (quick), `./gradlew check`
(full). Filter: `./gradlew test --tests {filter}`. Not parallel: Gradle locks.

**C# (.NET)**: `dotnet build -warnaserror` (quick, stop_on_fail),
`dotnet test --no-build --filter Category!=Slow` (quick),
`dotnet test --no-build` (full). Filter: `--filter FullyQualifiedName~{filter}`.

**C / C++ (CMake)**: `cmake --build build -j{jobs}` (quick, stop_on_fail),
`ctest --test-dir build -L unit -j{jobs}` (quick), `ctest --test-dir build -j{jobs}`
(full). Filter: `ctest --test-dir build -R {filter}`; `no_match_exit` is not
available, use `filter_match = 'Test +#\d+'`.

**Ruby**: `bundle exec rubocop` (quick), `bundle exec rspec spec/unit` (quick),
`bundle exec rspec` (full). Filter: `bundle exec rspec -e {filter}`.

**Shell scripts**: `shellcheck **/*.sh` (quick), `bats tests/` (full).

## 7. Adding kinds of stages

- **Lint / format check / types**: quick, before the tests, usually `stop_on_fail`
  for a compiler and not for a linter.
- **Build**: quick if incremental and fast, with `stop_on_fail = true`.
- **Smoke run** (start the real program briefly and fail on any error output): full.
  It catches what unit tests cannot: wiring, configuration, missing files.
- **End to end** (browser, device, container): full; `needs` + `if_missing = "skip"`
  when not every machine has the tool, and make sure CI does.

What is not a stage is not verified: add the stage rather than running a tool by hand.
