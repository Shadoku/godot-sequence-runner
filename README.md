# Sequence Runner

An XML-driven command sequencer for Godot 4. Define movement, animation, timing, and logic in XML files and play them back on any node.

## Getting Started

**Attach from the editor:** Add a child node, attach `sequence_runner.gd`, and set the `xml_path` export to your XML file. Enable `auto_start` to run on ready.

**Attach from code:**

```gdscript
var runner := sequence_runner.attach($Enemy, "res://data/sequences/patrol.xml", true)

# Or start manually
var runner := sequence_runner.attach($Enemy, "res://data/sequences/intro.xml")
runner.start()
```

**Pass variables in:** `start(path := "", vars := {}, section := "") -> bool` runs a section of the file at `path` (or `xml_path` when `path` is empty; `section` is the unnamed `<sequence>` when empty, see [Sections](#sections)). The scratch pad is reset on every `start()`, then `vars` are merged into it, so the sequence reads them as `$name`:

```gdscript
runner.start("res://data/sequences/attack.xml", {"damage": 12})
# or when attaching: attach(node, xml, auto := false, vars := {}, section := "") hands vars and section to start() when auto is true
sequence_runner.attach($Enemy, "res://data/sequences/attack.xml", true, {"damage": 12})
```

```xml
<call on="target" method="take_damage" arg0="$damage" />
```

Labels live apart from the variables (`labels`), so a variable may share a label's name.

**Listen for completion:**

```gdscript
runner.sequence_finished.connect(_on_sequence_done)
```

**Start and wait for the end:** `start_and_wait(path := "", vars := {}, section := "") -> bool` is a coroutine: it calls `start()` with the same arguments, then waits for `sequence_finished` only if the sequence is still running. Use it instead of `runner.start(); await runner.sequence_finished`, which hangs on a section of instant commands (it finishes, and emits `sequence_finished`, inside `start()`, before the `await` begins). It returns `false` at once when `start()` does (the file or section is missing), and `true` once the sequence has finished or was stopped.

```gdscript
if await runner.start_and_wait("res://data/cards/fireball.xml", {"caster": caster}, "on_play"):
    pass  # the section has played to its end (or was stopped)
```

A file whose `<trigger>` defers the start (`signal`, `timer`) is not waited for: `start_and_wait()` returns `true` at once and the sequence plays when its trigger fires.

**Stop a sequence:** `stop()` ends the running sequence: no further command runs (a `wait`, `wait_signal` or `call await` it was waiting on is abandoned, a `tween_move`'s tween is killed, a [`<run>`](#sub-sequences) child is stopped and freed), `running` turns `false` and `stopped` `true`, and `sequence_finished` is emitted at once, as at the end, so code waiting on it never hangs. It does nothing when no sequence runs; `start()` clears `stopped`. A sequence can stop itself with `<stop />` (or `<call on="self" method="stop" />`); `failed` stays `false`.

```gdscript
runner.start("res://data/sequences/patrol.xml")   # loops forever
# ... later, when the actor is removed:
runner.stop()
```

### Export Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `xml_path` | String (`*.xml` file) | `""` | Path to the XML sequence file |
| `auto_start` | bool | `false` | Run automatically on `_ready` |
| `target_self` | bool | `false` | Target the runner node instead of its parent |
| `verbose` | bool | `false` | Print debug output: the chosen target (`Targeting parent` / `Targeting self`) and each `goto` jump (`Jumping to: ...`) |
| `stop_on_error` | bool | `false` | Stop the sequence at its first run-time error and set `failed` (see [Errors and Validation](#errors-and-validation)); off, it carries on |
| `max_instant_steps` | int | `100000` | The most commands a sequence may run without waiting before it is stopped with an error and `failed`; `0`: no limit (see [Errors and Validation](#errors-and-validation)) |

## XML Format

```xml
<?xml version="1.0" encoding="UTF-8"?>
<data>
  <!-- Optional trigger -->
  <trigger type="signal" source="../Area2D" signal="body_entered" filter_group="player" />

  <sequence>
    <label name="start" />
    <move x="100" y="200" />
    <wait seconds="0.5" />
    <play_anim anim="idle" />
    <goto label="start" />
  </sequence>
</data>
```

### Sections

A file can hold any number of named sections, `<sequence name="...">`, beside at most one unnamed `<sequence>`: one file per actor, one section per moment the game plays it at. `start(path, vars, section)` runs one section (`""`, the default, is the unnamed one, so a file with a single unnamed `<sequence>` behaves as it always did). Labels belong to their section: two sections may use the same label names.

```xml
<data>
  <sequence name="on_hit">
    <call on="target" method="flash" />
  </sequence>
  <sequence name="on_removed">
    <play_anim anim="break" />
    <wait seconds="0.3" />
  </sequence>
</data>
```

```gdscript
runner.start("res://data/sequences/peg.xml", {}, "on_hit")
if not runner.start("res://data/sequences/peg.xml", {}, "on_spin"):
    pass  # the file has no section "on_spin": an error, nothing runs, sequence_finished is not emitted
```

A section the file lacks makes `start()` return `false` with an error; nothing runs and `sequence_finished` is not emitted. Two sections of the same name are an error (the second is ignored). To ask a file what it holds without running it:

| Static function | Returns |
|---|---|
| `sequence_runner.sections(path)` | the file's section names in file order (`""` for its unnamed `<sequence>`); empty, with an error, for a file that cannot be read |
| `sequence_runner.has_section(path, name)` | whether the file has that section |

## Commands

| Command | Attributes | Description |
|---|---|---|
| `move` | `x`, `y` | Set the target's `global_position` instantly |
| `tween_move` | `x`, `y`, `duration` | Smoothly move the target over a duration (async) |
| `wait` | `seconds` | Pause the sequence for a duration |
| `wait_signal` | `on` (default `target`), `signal` | Pause the sequence until that object emits the signal (async) |
| `label` | `name` | Define a named jump target |
| `goto` | `label` | Jump to a label |
| `goto_if` | `label`, `var`, `op`, `value` | Conditional jump (see below) |
| `if` … `else` … `/if` | `expr` | Run the commands inside when the [expression](#expressions) holds, else those after `<else/>` (optional; see [Blocks](#blocks)) |
| `else` | — | Inside an `<if>`: starts the part that runs when `expr` does not hold |
| `for_each` … `/for_each` | `var`, `in`, `index` (optional) | Run the commands inside once per element of an array (see [Blocks](#blocks)) |
| `set` | `var`, `value` or `expr` | Set a scratch pad variable to a token or an [expression](#expressions) |
| `set_prop` | `on` (default `target`), `prop`, `value` or `expr` | Write a property, a dictionary key or a vector component by path (see [Writing Properties](#writing-properties)) |
| `play_anim` | `anim`, `node_path` (optional) | Play an animation on the target or a child `AnimatedSprite2D` |
| `call` | `on`, `method`, `arg0`…`argN`, `var`, `await` | Call a method on a target object; `var` stores its return value, `await="true"` waits for it (see [Calling Methods](#calling-methods)) |
| `pause` | `time` | Pause the scene tree (optionally for a duration) |
| `unpause` | — | Unpause the scene tree |
| `stop` | — | End the sequence, as `stop()` does: `stopped` turns `true`, `failed` stays `false`, `sequence_finished` is emitted |
| `run` | `section`, `file` (optional), `var` (optional) | Play a section (of `file`, default the playing file) on a child runner and wait for it; `var` gets its `$result` (see [Sub-sequences](#sub-sequences)) |

### Variables

Set variables with `set` and reference them anywhere with the `$` prefix:

```xml
<set var="counter" value="0" />
<set var="counter" expr="$counter + 1" />
<move x="$spawn_x" y="$spawn_y" />
```

`set`'s `value` is resolved like any other token (`$other`, `random(...)`, `random_int(...)`), then typed (below); `expr` evaluates an expression. Variables can also be seeded from code with `start(path, vars)` (see Getting Started).

### Expressions

`set`'s and `set_prop`'s `expr` is a GDScript expression (Godot's `Expression` class): operators with their usual precedence, parentheses, comparisons, `and` / `or` / `not`, `a if c else b`, string literals in single quotes (`'fire'`, inside an XML attribute) and Godot's built-in functions and constructors (`abs`, `clamp`, `min`, `max`, `floor`, `round`, `sin`, `lerp`, `str`, `Vector2(...)`...):

```xml
<set var="x" expr="($left + $right) / 2" />
<set var="speed" expr="clamp($speed * 1.5, 0, $max_speed)" />
<set var="label" expr="'boss' if $hp > 100 else 'minion'" />
<set var="hot" expr="$element == 'fire'" />
<set var="roll" expr="random_int(1, 6) * 10 + random_int(1, 6)" />
<set_prop on="piece" prop="props.health" expr="$piece.props.health - $piece.props.step" />
```

**References.** `$name` and `$path.to.value` read as any other token does (the scratch pad, [Named Objects](#named-objects), [Property Paths](#property-paths), with the same errors), and a segment followed by `(` is left to the expression, so `$body.get_class()` calls the method on the object the path reads. Each reference is bound as an input before the expression runs.

**Numbers.** A reference that is an int, a bool or null reads as a float, as every other command reads its numbers (`$i + 1` is `2.0`, a flag adds as 1, an unresolvable reference, already reported, reads as 0); a string that reads as a number is one. Literals read as GDScript reads them: `$period / 2` is `0.5` when `period` is `1.0`, but `7 / 2` on two int literals is `3`. A string, a vector, an object, a dictionary or an array reads as it is (`$pos.length()`, `$name + '!'`).

**Functions.** Besides Godot's, `random(min, max)` and `random_int(min, max)` draw from the runner's `rng` ([Random Values](#random-values)). An expression sees nothing else: a bare name is an error.

**`<`, `>` and `&` in XML.** An expression sits in an XML attribute, where a bare `<` and `&` are not valid XML. Write them as the entities `&lt;`, `&gt;` and `&amp;`: Godot's `XMLParser` decodes them (and `&quot;`, `&apos;`, `&#60;`, `&#x3C;`) before the expression is compiled, so `expr="$hp &lt;= 0"` reads as `$hp <= 0` and `expr="$a &gt; 0 &amp;&amp; $b &gt; 0"` as `$a > 0 && $b > 0`. A bare `>` is valid XML and works as it is. (Godot's parser also happens to accept a bare `<` inside an attribute, but editors and other XML tools reject the file, so use `&lt;`; `and`, `or` and `not` need no escaping at all.)

**Errors.** An expression that does not parse is a compile problem (`validate()` lists it, `start()` pushes it) and the command does nothing. A failure while it runs (an unknown function, a member it cannot read, `'a' + 1`, a division by zero, a float that overflows) is an error and the expression reads as `0`; the sequence carries on. Expressions are compiled with their section and executed per run.

### Typed Values

A token's resolved value is typed before `call` passes it as an argument and before `set` or `set_prop` stores it (`to_value()`):

| Token | Value |
|---|---|
| `true`, `false` (any case: `True`, `FALSE`) | that `bool` |
| `6`, `-2`, `0.5` | the `int` or `float` it reads as |
| `'7'`, `'true'` (wrapped in single quotes) | the `String` inside, whatever it reads as |
| anything else (`hello`) | the `String` as it is |

```xml
<call on="target" method="set_visible" arg0="false" />
<call on="target" method="say" arg0="'42'" />       <!-- the string "42", not the int -->
<set var="armed" value="true" />
```

### Random Values

Any token field accepts `random(min, max)` for a random float or `random_int(min, max)` for a random integer:

```xml
<move x="random(0, 800)" y="random(0, 600)" />
<wait seconds="random(0.5, 2.0)" />
<set var="roll" value="random_int(1, 6)" />
<set var="roll" expr="random_int(1, 6) * 10 + random_int(1, 6)" />   <!-- the function form, inside an expression -->
```

They draw from the global generator unless the runner's `rng` is set: give it a seeded `RandomNumberGenerator` (a game's run seed, say) and the sequence rolls the same values every time it is played from the same state, without disturbing the global generator.

```gdscript
var dice := RandomNumberGenerator.new()
dice.seed = run_seed
runner.rng = dice
runner.start("res://data/sequences/scatter.xml")
```

### Property Paths

Variable tokens can reference object properties with dot notation. `Vector2` and `Vector3` components (`.x`, `.y`, `.z`) are supported. The path's head is resolved like `call`'s `on` (see [Named Objects](#named-objects)), so it can start from an object handed in with `start()`; a path of one segment is the object itself (`$target`, `$self`):

```xml
<move x="$target.global_position.x" y="$target.global_position.y" />
<call on="target" method="take_damage" arg0="$body.radius" />
```

Paths step into a `Dictionary` by key, whether it is an object's property or a scratch-pad variable itself:

```gdscript
runner.start("res://data/sequences/peg.xml", {"piece": peg, "stats": {"bonus": 2}})   # peg.props == {"health": 3}
```

```xml
<goto_if label="broken" var="$piece.props.health" op="le" value="0" />
<call on="target" method="add_score" arg0="$stats.bonus" />
```

Paths step into an `Array` (or a packed array, such as a `PackedStringArray`) by index, counted from 0:

```gdscript
runner.start("res://data/cards/volley.xml", {"targets": [goblin, troll], "card": {"tags": ["fire", "flying"]}})
```

```xml
<call on="target" method="hit" arg0="$targets.0" />
<goto_if label="burn" var="$card.tags.0" op="eq" value="fire" />
<set var="first_hp" expr="$targets.0.health" />
```

A segment indexes an array only when it is all digits (`0`, `12`); there are no negative indices. An index past the end is a segment that cannot be read, as a missing key is.

A segment that cannot be read (a missing dictionary key, a property the object lacks, an index out of range) is an error and the reference reads as `null`; numeric commands (`move`, `wait`, expressions...) read `null` as `0`. Writing through a path is [`set_prop`](#writing-properties)'s job, and creates a missing key.

### Named Objects

Objects handed in with `start(path, vars)` can be addressed by name wherever an object is expected: `on` in `call` and `wait_signal`, and the head of a property path. `on` (and a path's head) resolves, in order, to:

1. `target` (the runner's parent, or the runner with `target_self`) and `self` (the runner);
2. a scratch-pad variable of that name holding an `Object` (`on="body"` and `on="$body"` are the same);
3. the node at that path from `/root/` (cached for the run).

```gdscript
runner.start("res://data/sequences/bounce.xml", {"body": body, "peg": peg})
```

```xml
<call on="peg" method="flash" />
<call on="body" method="apply_impulse" arg0="$peg.strength" />
<wait_signal on="body" signal="settled" />
```

A scratch-pad object that has been freed is an error (the command finds no object). Scratch-pad objects are looked up each time, not cached, so `set` can point a name at another object mid-sequence.

### Writing Properties

`set_prop` writes at the path `prop` of the object `on` names (resolved like `call`'s, or a scratch-pad dictionary or array), with `value` (a token, resolved like `set`'s) or `expr` (an [expression](#expressions), as `set`'s). The path's last segment is an object's property, a dictionary key (created when missing), an array index within the array's size (an array never grows) or a `Vector2` / `Vector3` component (the vector is read, changed and written back, so `position.x` moves the node):

```xml
<set_prop on="world" prop="gravity_scale" value="0.5" />
<set_prop on="piece" prop="props.health" expr="$piece.props.health - 1" />
<set_prop prop="position.x" value="120" />
<set_prop on="stats" prop="combo" value="0" />
<set_prop on="hand" prop="0" value="$drawn" />          <!-- the first element of the array $hand -->
<set_prop on="card" prop="tags.1" value="'cold'" />
```

An object it cannot find, or a segment it cannot read or write (an index out of range, an element of a packed array, which is a copy), is an error and nothing is written.

### Conditional Jumps

`goto_if` compares two values and jumps if the condition is true.

Operators: `eq`, `!=`, `<`, `>`, `<=`, `>=`, `mod` (true when `a % b == 0`), and the word aliases `lt` (`<`), `gt` (`>`), `le` (`<=`) and `ge` (`>=`). An XML attribute may not hold a bare `<`, so prefer the aliases: `op="lt"` rather than `op="<"`. Any other operator is an error, and nothing jumps.

```xml
<goto_if label="done" var="$counter" op=">=" value="5" />
<goto_if label="none" var="$bin" op="lt" value="0" />   <!-- below 0 -->
```

Each operand (`var` and `value`) is a scratch-pad variable's name or any token (`$name`, a path, a literal), typed as in [Typed Values](#typed-values). Two numbers (or bools, as 0 and 1) compare as numbers. When either operand is a string that does not read as a number, `eq` and `!=` compare the two as strings, and the other operators (the aliases too) are an error (nothing jumps):

```xml
<goto_if label="burn" var="$element" op="eq" value="fire" />
<goto_if label="skip" var="$body.tag" op="!=" value="'7'" />   <!-- quoted: compared with the string "7" -->
```

An operand that cannot be resolved is an error, and nothing jumps.

### Blocks

`<if>` and `<for_each>` hold commands between their start and end tags, so a sequence can branch and loop without labels:

```xml
<if expr="$target.health &lt;= 0">
  <call on="board" method="destroy" arg0="$target" />
<else />
  <call on="target" method="flash" />
</if>

<for_each var="enemy" in="$enemies" index="i">
  <call on="enemy" method="take_damage" arg0="2" />
  <wait seconds="0.1" />
</for_each>
```

**`<if expr="...">`** evaluates `expr`, an [expression](#expressions) compiled with the section as `set`'s is. When the result is truthy (`true`, a number other than 0, a non-empty string or array, an object) the commands up to `<else/>` (or up to `</if>`) run and those after `<else/>` are skipped; otherwise the first part is skipped and the part after `<else/>` runs. `<else/>` is optional. Write `<` as `&lt;` (see [Expressions](#expressions)). A missing `expr`, or one that does not parse, is a compile problem and reads as false. An `<else/>` that is not directly inside an `<if>` (at the top of a section, or inside a `<for_each>` inside the `<if>`) is a compile problem and does nothing, as is a second `<else/>` in one `<if>`.

**`<for_each var="m" in="$list" index="i">`** resolves `in` as a token (`$list`, a path such as `$board.enemies`, `$card.targets.0`) to an `Array` (or a packed array), takes a copy of it, and runs the commands inside once per element, with `$m` set to the element and `$i` (when `index` is given) to its position from 0, an int. The copy is taken when the loop is entered, so changing the source array inside the body (a card that dies and leaves the board mid-loop) does not shift or shorten the rounds. An empty array skips the body; something that is not an array is an error and skips the body too. A missing `in` is a compile problem. After the loop, `$m` and `$i` keep the last round's values.

**Nesting, labels and `goto`.** Blocks nest in any combination (a loop in a loop, an `<if>` in a loop, a loop in an `<if>`). Labels inside blocks work as anywhere else: a `goto` to a label just before `</for_each>` goes on to the next round, and a `goto` (or `goto_if`) to a label outside a loop abandons it, so entering that `<for_each>` again from above starts a fresh loop over a fresh copy, and jumping back into an abandoned loop's body runs it once to `</for_each>` and goes on past it. Loop state lives in the runner (per `<for_each>`), not in the scratch pad, and `start()` clears it.

**How it is read.** The reader stays flat: only `<if>` and `<for_each>` get an extra end marker command (`end_if`, `end_for_each`) where they end (at once when self-closed, `<if expr="..." />` being an empty block). Every other element reads as before, nested or not: `<wait seconds="1"></wait>` is one `wait`, and an element nested in another is simply the next command. The compiler pairs `<if>`, `<else/>` and the markers with a stack. The marker names `end_if` and `end_for_each` are therefore taken; do not write them as elements.

**A subclass's own `if` or `for_each`.** A subclass that registers a command named `if` or `for_each` (after `super.register_commands()`) keeps it: its factory builds the command as any other, and that name's end markers compile to no-ops without a compile problem. `<else/>` stays the built-in one, so with a subclass's own `if` it is reported as outside an `<if>` unless the subclass registers `else` too.

### Sub-sequences

`<run>` plays another section as a sub-sequence and waits until it ends, so sections can share steps (one section per card hook, a common "deal damage" section they all run):

```xml
<sequence name="on_play">
  <run section="deal_damage" var="dealt" />
  <run file="res://data/cards/common.xml" section="draw_one" />
  <call on="log" method="add" arg0="$dealt" />
</sequence>
<sequence name="deal_damage">
  <call on="target_card" method="take_damage" arg0="$amount" var="result" />
</sequence>
```

**`<run section="..." file="..." var="..." />`** plays the section `section` (`""` or left out: the unnamed `<sequence>`) of the file `file` (left out: the playing file) on a child runner:

- The child is an instance of the caller's own script (`get_script().new()`), so a subclass's commands work in it, added as the caller's child, with the caller's `target`, `rng`, `verbose`, `stop_on_error` and `max_instant_steps`.
- It starts with a shallow copy of the caller's scratch pad: it reads the caller's variables, and objects, dictionaries and arrays are shared (a `set_prop` or a `call` on one changes what the caller sees), but its own `set`s do not leak back. `$result` is left out of the copy: the child starts without one.
- `var` (optional) stores the child's `$result` variable in the caller's scratch pad when it ends; `null` when the child set none.
- The file's `<trigger>` is ignored: the section plays at once. (A plain `start()` on that file still follows its trigger.)
- `<run>` is instant when the child ends inside its start (a section of instant commands: no frame passes, and a caller made of instant commands still finishes inside `start()`), and async otherwise: the caller waits for the child, as for a `wait`.
- The child is freed when it ends. A `<stop/>` in the child ends the child only; the caller goes on.
- `file` and `section` are tokens: `file="$card_file" section="$hook"` resolves them when the command runs.

**Errors.** A section the file lacks is a compile problem (`validate()` lists it) when `file` is left out or is a literal path to a file that can be read; when `file` or `section` is a `$` reference, or the file cannot be read, it is a run-time error, and nothing runs. With `stop_on_error` on, an operand that cannot be resolved stops the caller before any child is made.

**Failing and stopping.** A child that `failed` (a run-time error with `stop_on_error` on, or `max_instant_steps`) makes the caller fail too when the caller's `stop_on_error` is on: a run-time error naming the sub-sequence is reported, `failed` turns `true` and the caller stops (its `var` is not written). With `stop_on_error` off the caller carries on after it. `stop()` on the caller stops its running child (and so on down), which is then freed.

**Depth.** Runs nest: a child may `<run>` too. `MAX_RUN_DEPTH` (32) caps the nesting: the runner the game starts is depth 0, its child depth 1; a `<run>` that would go past 32 is a run-time error and runs nothing, so a section that runs itself forever ends with an error instead of a crash. Each child counts its own `max_instant_steps` (given the caller's limit), so the depth cap, not the step cap, ends an instant section that runs itself.

**Shared caches.** Parsed files, label maps and triggers are cached per file for every runner; a child playing another section of the same file has its own `labels`, `sequence`, `index` and `current_section`, and leaves the caller's alone.

**From code: `run_once()`.** `sequence_runner.run_once(host, path, vars := {}, section := "", runner_script: Script = null) -> bool` is a static coroutine: it attaches a temporary runner (an instance of `runner_script`, `sequence_runner` when null) to `host`, which it targets, plays the section with `vars` seeding its scratch pad (the file's `<trigger>` ignored), waits until it ends, frees the runner and returns `true` when it played to its end (a `<stop/>` counts) and `false` when the section is missing or the run `failed`. One runner per call is what lets a card's trigger play while another effect is still resolving:

```gdscript
var strict := preload("res://game/strict_runner.gd")   # a subclass with stop_on_error on, say
if not await sequence_runner.run_once(card, "res://data/cards/fireball.xml", {"target": enemy}, "on_play", strict):
    pass  # missing section, or an error cut the effect short
```

If `host` is freed (or leaves the tree) while the section plays, the runner is stopped (and freed, with the host or by `run_once()`), and `run_once()` returns `false` one frame later, outside the freeing. It is named `run_once` because a known subclass already has a static `play()`.

### Calling Methods

`call` targets `"target"` (parent) by default. Use `"self"` for the runner, the name of an object handed in with `start()` (see [Named Objects](#named-objects)), or a path from `/root/`. Targets resolved from `/root/` are cached for the duration of the run.

Arguments are resolved like any token (`$var`, `random(...)`, `random_int(...)`), then typed (see [Typed Values](#typed-values)): `"6"` is passed as the int `6`, `"0.5"` as the float `0.5`, `"true"` as the bool `true`, so methods with typed parameters (`func take_damage(n: int)`) can be called; `'6'` in single quotes is passed as the string `"6"`. Any other string is passed as it is.

```xml
<call method="queue_free" />
<call on="target" method="set_health" arg0="100" />
<call on="target" method="take_damage" arg0="$damage" />
<call on="Game/UI/HUD" method="show_message" arg0="Hello!" />
```

**Return values.** `var="name"` stores what the method returns in the scratch pad, for later commands to read as `$name`:

```xml
<call on="world" method="spawn" arg0="12" var="blob" />
<call on="blob" method="set_velocity" arg0="0" arg1="-200" />
```

**Waiting for a call.** `await="true"` makes `call` wait, depending on what the method gives back:

| The method | `await="true"` |
|---|---|
| returns a `Signal` | waits for that signal |
| awaits something itself (a coroutine: calling it hands back its state, a `GDScriptFunctionState`, until it returns) | waits until the method returns; `var` then gets its final return value |
| returns anything else | goes on at once (the method has already finished) |

```xml
<call on="target" method="play_intro" await="true" />          <!-- func play_intro() -> void: await ...; ... -->
<call on="dialog" method="ask" arg0="Continue?" await="true" var="answer" />
```

Without `await`, a coroutine runs on by itself while the sequence goes on, and `var` holds `null` (the method has not returned yet).

### Waiting for Signals

`wait_signal` pauses the sequence until an object emits a signal, so a sequence can wait for the game (a `call` followed by a `wait` cannot). `on` is resolved like `call`'s (`target` by default, `self`, a named object, or a path from `/root/`). If the object or the signal does not exist, it prints an error and the sequence carries on without waiting.

```xml
<call on="target" method="drop" />
<wait_signal on="target" signal="drop_finished" />
<play_anim anim="celebrate" />
```

### Animation

`play_anim` looks for an `AnimatedSprite2D` in this order: the target itself, the node at `node_path` (relative to the target) if provided, or the first `AnimatedSprite2D` found recursively in the target's children. The result is cached after the first lookup, per `node_path`.

```xml
<play_anim anim="walk_right" />
<play_anim anim="attack" node_path="Visuals/Sprite" />
```

## Triggers

Place a `<trigger>` before `<sequence>` to control when it starts.

| Type | Attributes | Behavior |
|---|---|---|
| `auto` | — | Runs immediately |
| `manual` | — | Runs when code calls `runner.start()` (no `auto_start`) |
| `signal` | `source`, `signal`, `filter_group` | Waits for a signal from a relative node |
| `timer` | `seconds` | Starts after a one-shot delay |

```xml
<trigger type="signal" source="../HitBox" signal="body_entered" filter_group="player" />
<trigger type="timer" seconds="3.0" />
```

## Examples

**Patrol loop:**
```xml
<sequence>
  <label name="start" />
  <move x="100" y="200" />
  <wait seconds="2.0" />
  <move x="300" y="200" />
  <wait seconds="2.0" />
  <goto label="start" />
</sequence>
```

**Smooth patrol with tweens:**
```xml
<sequence>
  <label name="start" />
  <play_anim anim="walk_right" />
  <tween_move x="300" y="200" duration="2.0" />
  <play_anim anim="walk_left" />
  <tween_move x="100" y="200" duration="2.0" />
  <goto label="start" />
</sequence>
```

**Counted loop:**
```xml
<sequence>
  <set var="i" value="0" />
  <label name="loop" />
  <call on="target" method="flash" />
  <wait seconds="0.3" />
  <set var="i" expr="$i + 1" />
  <goto_if label="done" var="$i" op=">=" value="5" />
  <goto label="loop" />
  <label name="done" />
</sequence>
```

**Random movement:**
```xml
<sequence>
  <label name="wander" />
  <tween_move x="random(50, 750)" y="random(50, 550)" duration="random(1.0, 3.0)" />
  <wait seconds="random(0.5, 2.0)" />
  <goto label="wander" />
</sequence>
```

**Chain into another sequence** (the runner switches to it at once; its scratch pad is reset):
```xml
<call on="self" method="start" arg0="res://data/sequences/phase_2.xml" />
```

**Wait for the game:**
```xml
<sequence>
  <call on="target" method="start_turn" />
  <wait_signal on="target" signal="turn_finished" />
  <call on="Game/UI/HUD" method="show_message" arg0="Your move" />
</sequence>
```

## Extending

Add a command in three steps:

**1. Command function** — returns a `Callable` that returns `null` (instant) or a `Signal` (async) on every path:

```gdscript
func cmd_scale(x_token: String, y_token: String) -> Callable:
    return func() -> Variant:
        var x := to_float(resolve_value(x_token))
        var y := to_float(resolve_value(y_token))
        target.scale = Vector2(x, y)
        return null
```

A problem met while it runs (a value it cannot use, an object that is gone) goes through `run_error(message)`, which pushes an error naming the file and section. With `stop_on_error` on, `run_error()` also stops the sequence and sets `failed`; a command that resolves its operands first and acts after should then check `failed` in between, as the built-ins do, so it has no side effect once an operand failed:

```gdscript
        var x := to_float(resolve_value(x_token))
        if failed:
            return null
```

**2. Factory function** — maps XML attributes to command arguments (the second argument is the command's index in the compiled sequence). A bad attribute *value* it can see at compile time goes through `compile_error(message)`, so `validate()` lists it too:

```gdscript
func factory_scale(args: Dictionary, _index: int) -> Callable:
    if not args.has("x"):
        compile_error("<scale> needs x")
    return cmd_scale(str(args.get("x", "1")), str(args.get("y", "1")))
```

**3. Register** in `register_commands()`, with the attributes it accepts (any other is a compile problem; an entry ending in `*` stands for that prefix followed by digits, as `call`'s `arg*`):

```gdscript
register_command("scale", factory_scale, PackedStringArray(["x", "y"]))
```

Then use it: `<scale x="2" y="2" />`

For project-specific commands, subclass and call `super.register_commands()` to keep the built-ins:

```gdscript
class_name MySequenceRunner
extends sequence_runner

func register_commands() -> void:
    super.register_commands()
    register_command("scale", factory_scale, PackedStringArray(["x", "y"]))
```

A factory put straight into `command_factories` (`command_factories["scale"] = factory_scale`, the older way) still works; its attributes are then not checked.

## Errors and Validation

Every problem is reported with `push_error`, so it shows as an `ERROR:` line (and in the debugger's Errors tab), never as bare text a test could miss.

**Compile problems** are found when a section is compiled (by `start()`, or by `validate()`): an unknown command, an unknown attribute of a known command, a `goto` or `goto_if` to a label the section lacks, an `expr` that does not parse, an `<if>` without `expr`, a `<for_each>` without `in`, an `<else/>` outside an `<if>` or a second one in the same `<if>`, a `<run>` to a section its (literal or left out) file lacks, what a factory reports with `compile_error()`; and in the file itself, a second section of the same name or no section at all. `start()` pushes each one as an error, counts them in `compile_errors` and still runs the section (an unknown command does nothing). A section `start()` is asked for and the file lacks is an error too, and nothing runs.

**Run-time problems** are errors pushed while the sequence plays, and the sequence carries on: an unresolvable variable or path, a missing object, method, signal or dictionary key, a `goto_if` operand it cannot compare, an expression that fails (an unknown function, a division by zero), a `<for_each>` whose `in` is not an array, a `<run>` to a missing section or past `MAX_RUN_DEPTH`, a `<run>` child that failed (only with `stop_on_error` on, see [Sub-sequences](#sub-sequences)).

**Stopping at the first run-time error.** With `stop_on_error = true` (an export, `false` by default), the first run-time error sets `failed = true` and stops the sequence as `stop()` does: `running` turns `false`, `stopped` `true`, and `sequence_finished` is emitted once. The command that met the error has no side effect after it: a built-in command checks for the error after resolving its operands and before acting, so `call` does not call the method (nor store `var`), `set` and `set_prop` do not write, `move` and `tween_move` do not move, `goto_if` does not jump, `pause` does not pause, `wait` and `wait_signal` do not wait. An error reported while the sequence waits (by game code calling `evaluate_expr()`, say) stops it too, and the wait is abandoned. `start()` clears `failed`. Errors pushed outside `run_error()` (a compile problem, a missing file or section, `to_float()`'s "not a number") do not set it.

**A loop that never waits.** `max_instant_steps` (an export, `100000` by default) caps how many commands a sequence runs without waiting. A command that returns a signal (`wait`, `tween_move`, `wait_signal`, `call await`) makes the loop wait, and the count restarts after it; the waiting command itself counts before it waits. Past the cap, before the next command runs, an error naming the file, section and cap is pushed, `failed` turns `true` and the sequence stops as `stop()` does, whatever `stop_on_error` says, so a `goto` loop that forgot its `wait` stops instead of freezing the game. A chain hand-over (`start()` from inside the sequence) does not wait, so the count carries on into the new sequence. `0` disables the cap.

```
ERROR: sequence_runner: res://data/sequences/patrol.xml:: more than 100000 commands without waiting (max_instant_steps); the sequence is stopped
```

```gdscript
runner.stop_on_error = true
await runner.start_and_wait("res://data/cards/fireball.xml", {"target": card}, "on_play")
if runner.failed:
    pass  # an error cut the effect short; nothing ran after it
```

**Checking files without running them.** `validate(path) -> PackedStringArray` compiles every section of a file and returns one line per problem, without running anything and without pushing an error:

```
res://data/sequences/peg.xml: a second section "on_hit" (ignored)
res://data/sequences/peg.xml:: unknown command <cal>
res://data/sequences/peg.xml:on_hit: <set> has no attribute "valu"
res://data/sequences/peg.xml:on_hit: <goto> to a label the section lacks: "done"
res://data/sequences/old.xml: no section (no <sequence> element)
res://data/sequences/gone.xml: cannot be read
```

(`<file>:<section>: <problem>`, the section empty for the unnamed one; `<file>: <problem>` for the file itself.) An empty array means the file is sound. It is an instance method so that a subclass's commands count, and it registers the commands itself, so a runner that is not in the tree can check every file of a project, in a test:

```gdscript
var runner := MySequenceRunner.new()
for file in DirAccess.get_files_at("res://data/sequences/"):
    assert(runner.validate("res://data/sequences/" + file).is_empty())
runner.free()
```

## Architecture

The pipeline is **Parse → Compile → Run**. XML is parsed into dictionaries, one flat list per section (`read_sections(path)`: section name → its commands, the unnamed one under `""`; an `<if>` or `<for_each>` is followed where it ends by an end marker command, `end_if` or `end_for_each`), and the section `start()` names is compiled into an `Array[Callable]` via factory functions (blocks are paired first, so an `<if>`, its `<else/>` and a `<for_each>` know the index to jump to, and a `<for_each>`'s end marker jumps back), then executed sequentially (`run_sequence()`: an async command's signal resumes the loop through the runner's own `_resumed`, tagged with the run, so `stop()` can end a waiting run at once). Expressions (`expr`) are compiled with their section (`compile_expr()`: the `$` references become the inputs of a Godot `Expression`, parsed once) and executed per run (`run_expr()`). Labels are pre-scanned per section (`label_map()`) and stored separately from the command array as index pointers (`labels`, and `label_cache[path][section]`). Parsed XML, label maps, and trigger configs are all statically cached so multiple runners sharing a file do no redundant work. Runtime state lives in a per-run `scratch_pad` dictionary that resets on each `start()` call (then takes the `vars` passed to it); the state of the `<for_each>` loops under way is kept apart from it, per `<for_each>` command, and also reset by `start()`. Targets resolved from `/root/` (by `call`, `wait_signal` or a property path) are also cached in the scratch pad to avoid repeated lookups; named objects are read from it as they are. A `<run>` plays its section on a child runner (`_start_section()` with the trigger ignored) and, when the child does not end inside its start, hands the loop the `completed` signal of a coroutine that waits for the child's `sequence_finished`, stores `var` and frees the child.

## What's new

Every public name added since the regression suite, so a subclass can check it does not already use one:

| Name | Kind | See |
|---|---|---|
| `start_and_wait(path, vars, section) -> bool` | method (coroutine) | [Getting Started](#getting-started) |
| `stop_on_error` | export (bool, default `false`) | [Errors and Validation](#errors-and-validation) |
| `failed` | member (bool) | [Errors and Validation](#errors-and-validation) |
| `max_instant_steps` | export (int, default `100000`) | [Errors and Validation](#errors-and-validation) |
| `<stop />` | command | [Commands](#commands) |
| `factory_stop(args, index) -> Callable` | method (the `stop` command's factory) | [Extending](#extending) |
| `<if expr>`, `<else />`, `<for_each var in index>` | commands | [Blocks](#blocks) |
| `end_if`, `end_for_each` | command names the reader adds after `<if>` and `<for_each>` (only those two elements) | [Blocks](#blocks) |
| `factory_if_block()`, `factory_else_block()`, `factory_for_each_block()` | methods (the block commands' factories) | [Blocks](#blocks) |
| `<run section file var />` | command | [Sub-sequences](#sub-sequences) |
| `factory_run_section(args, index) -> Callable` | method (the `run` command's factory) | [Sub-sequences](#sub-sequences) |
| `MAX_RUN_DEPTH` | constant (int, `32`) | [Sub-sequences](#sub-sequences) |
| `run_once(host, path, vars, section, runner_script) -> bool` | static method (coroutine) | [Sub-sequences](#sub-sequences) |

Without a new name:

- **Array indices in property paths**: `$list.0`, `$card.tags.1`, and `set_prop`'s `prop="list.0"` ([Property Paths](#property-paths), [Writing Properties](#writing-properties)). `read_member()` and `write_member()` take an index for an `Array` (and `read_member()` for a packed array). A path that indexes an array was an error before.
- **`&lt;` in expressions**: Godot's `XMLParser` decodes `&lt;`, `&gt;` and `&amp;` in attributes, so an `expr` can hold `<` ([Expressions](#expressions)).

## Development

The addon is the one file `sequence_runner.gd`; everything else in the repository checks it. `python3 tools/check.py` runs the tests headless (Godot 4.7, the version in `.godot-version`; `bash tools/install_godot.sh` downloads it) and ends with `CHECK: PASS` or `CHECK: FAIL`. `CLAUDE.md` has the working rules, the test layout and the compatibility rules a change must keep.
