# Plan: additions for scripted card games

Status: agreed 2026-11-13. Steps 0 to 5 are done. Step 6 (docs) was written with
each feature (a README section per feature and the "What's new" table).

## Why

The runner suits the card-effect layer of a trading card game (one file per card, one
section per hook, `call ... await` for targeting), but six things are missing on the
addon side. Game state, zones, the effect queue's ordering and passive modifiers stay in
the game.

## Compatibility rules (every step)

Projects in use copy `sequence_runner.gd`, and some subclass it (goo_pachinko's
`GameSequenceRunner`, which has a static `play()`).

- No existing signature, default, signal, signal timing, command or attribute changes.
- New behaviour is a new method, a new command, a new attribute, or an export whose
  default is today's behaviour. The one agreed exception: `max_instant_steps` defaults
  to 100000 (it only fires where the game would otherwise hang).
- `start()` while a sequence runs still chains into the new one (the README's "Chain
  into another sequence").
- A subclass's command registered after `super.register_commands()` keeps winning over
  a built-in of the same name.
- New public names must be distinctive: a subclass that already defines the same method
  with another signature stops compiling. Every new name is listed in the README.
- `tests/unit/test_sequence_runner.gd` is not edited. Each feature adds its own test file
  `tests/unit/test_<feature>.gd` and fixtures `tests/fixtures/sequences/<feature>*.xml`.
- The addon stays one self-contained file.

## Steps

One commit per feature: tests, the change, its README section.

### 0. Regression suite and check (done)

`python3 tools/check.py`; `tests/unit/test_sequence_runner.gd` pins the existing
behaviour.

### 1. `start_and_wait(path := "", vars := {}, section := "") -> bool`

A coroutine. It calls `start()` and returns `false` at once when `start()` does. If not,
it waits for `sequence_finished` only if the sequence is still `running`, and returns
`true`. Fixes the hang of `runner.start(); await runner.sequence_finished` on a section
of instant commands (it finishes inside `start()`). A file whose `<trigger>` defers the
start (signal, timer) is not waited for. Say so in the doc comment and README.

### 2. `stop_on_error`, `failed`, `<stop/>`

- `@export var stop_on_error: bool = false`. Off: run-time errors carry on, as today.
  On: the first `run_error()` sets `failed = true` and stops the sequence (`stop()`:
  `stopped` true, `sequence_finished` emitted once).
- `var failed: bool = false`, cleared by `start()`.
- With `stop_on_error` on, the command that met the error has no side effect after it:
  a built-in command checks whether the run was stopped after resolving its operands
  and before acting (`call` does not call the method, `set` / `set_prop` do not write,
  `move` / `tween_move` do not move, `goto_if` does not jump...).
- `<stop/>`: a command without attributes that calls `stop()`. `failed` stays false.

### 3. `max_instant_steps`

`@export var max_instant_steps: int = 100000` (0: no limit). The run loop counts the
commands run since it last waited. Past the limit it pushes an error naming the file,
section and limit, sets `failed = true` and stops the sequence, whatever
`stop_on_error` says. The count restarts each time the loop waits.

### 4. Sub-sequences: `<run>` and `run_once()`

- `<run section="..." file="..." var="..." />`: runs a section (of `file`, default the
  caller's file) on a child runner and waits until it finishes. The child is an instance
  of the caller's own script (a subclass's commands work), added as the caller's child,
  with the caller's `target`, `rng`, `verbose`, `stop_on_error`, `max_instant_steps`.
  It gets a shallow copy of the caller's scratch pad: objects and dictionaries are
  shared, the child's own `set`s do not leak back. `var` stores the child's `$result`
  variable in the caller's scratch pad (null when the child set none). The file's
  `<trigger>` is ignored. The section runs at once. The child is freed when done.
- Instant when the child finished inside its start, async otherwise.
- Depth limit `MAX_RUN_DEPTH` (32): deeper is a run-time error and nothing runs.
- A child that `failed` makes the caller fail too when `stop_on_error` is on. The
  caller's `stop()` stops its running children.
- A missing section is a compile error when `file` is absent or a literal that can be
  read, and a run-time error otherwise.
- `static func run_once(host: Node, path: String, vars := {}, section := "", runner_script: Script = null) -> bool`:
  a coroutine that attaches a temporary runner (of `runner_script`, default this
  script) to `host`, runs the section (trigger ignored), waits, frees the runner, and
  returns whether it ran to its end without failing. One runner per resolving effect
  lets a trigger fire while another effect resolves.

### 5. Blocks: `<if>`, `<else/>`, `<for_each>`, array indices in paths

- `<if expr="..."> ... <else/> ... </if>`: `expr` as `set`'s (compiled with the section,
  truthy runs the first part). `<else/>` is optional.
- `<for_each var="m" in="$list" index="i"> ... </for_each>`: `in` is a token resolving
  to an Array. The loop iterates a copy taken on entry (a card dying mid-loop does
  not shift it) and sets `$m` (and `$i`, optional, from 0) per round. An empty array skips
  the body. Something that is not an Array is a run-time error and skips the body.
- Blocks nest. Labels and `goto` work inside them. A `goto` out of a loop abandons it
  (entering the `for_each` again from above starts afresh).
- Parsing: the reader stays flat. Only for the element names `if` and `for_each` it
  appends an end marker (`end_if`, `end_for_each`) at the element's end (at once
  for a self-closed one). Any other nested element reads as before.
  The compiler pairs openers, `else` and end markers with a stack and reports an `else`
  outside an `if`. When a subclass registered its own `if` or `for_each`, its factory
  wins and the end markers of that name compile to no-ops without an error.
- Loop state lives in the runner (per command index), not in the scratch pad, and is
  cleared by `start()`.
- Paths index arrays: `$list.0`, `$card.tags.1`, and `set_prop prop="list.0"` (an index
  out of range is the usual "has no" error). Today that is an error, so nothing changes
  for working files.
- Check and document whether `&lt;` works inside an `expr` attribute (Godot's XMLParser
  may not decode entities). If not, document `not (a >= b)` style or add nothing.

### 6. Docs

A README section per feature (written with the feature) and a "What's new" list of
every new public name: methods, exports, members, commands, attributes, constants.

## Order

Steps 1 to 3 touch the run loop and go together, in order. Step 5 touches the reader
and compiler and can be built beside them. Step 4 builds on 1 to 3.

## Left out on purpose

- Expressions keep reading ints as floats (`$i / 2` would change). Use `int(...)`.
- Passive effects (auras, cost modifiers) and the effect queue stay in the game.
- A `wait_signal` on several signals: `call await` on a game method covers it.
