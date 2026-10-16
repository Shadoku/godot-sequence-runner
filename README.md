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

**Pass variables in:** `start(path := "", vars := {})` runs the sequence at `path` (or `xml_path` when `path` is empty). The scratch pad is reset on every `start()`, then `vars` are merged into it, so the sequence reads them as `$name`:

```gdscript
runner.start("res://data/sequences/attack.xml", {"damage": 12})
# or when attaching: attach(node, xml, auto := false, vars := {}) hands vars to start() when auto is true
sequence_runner.attach($Enemy, "res://data/sequences/attack.xml", true, {"damage": 12})
```

```xml
<call on="target" method="take_damage" arg0="$damage" />
```

Labels are merged after the variables, so a variable named like a label is replaced by the label.

**Listen for completion:**

```gdscript
runner.sequence_finished.connect(_on_sequence_done)
```

### Export Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `xml_path` | String (`*.xml` file) | `""` | Path to the XML sequence file |
| `auto_start` | bool | `false` | Run automatically on `_ready` |
| `target_self` | bool | `false` | Target the runner node instead of its parent |
| `verbose` | bool | `false` | Print debug output: the chosen target (`Targeting parent` / `Targeting self`) and each `goto` jump (`Jumping to: ...`) |

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
| `set` | `var`, `value`, `expr` | Set a scratch pad variable |
| `play_anim` | `anim`, `node_path` (optional) | Play an animation on the target or a child `AnimatedSprite2D` |
| `call` | `on`, `method`, `arg0`…`argN` | Call a method on a target object |
| `pause` | `time` | Pause the scene tree (optionally for a duration) |
| `unpause` | — | Unpause the scene tree |

### Variables

Set variables with `set` and reference them anywhere with the `$` prefix:

```xml
<set var="counter" value="0" />
<set var="counter" expr="$counter + 1" />
<move x="$spawn_x" y="$spawn_y" />
```

Expressions support basic arithmetic: `$a + 1`, `$speed * 2`, `$hp - 25`, `$total / 4`.

`set`'s `value` is resolved like any other token (`$other`, `random(...)`, `random_int(...)`); `expr` evaluates arithmetic. Variables can also be seeded from code with `start(path, vars)` (see Getting Started).

### Random Values

Any token field accepts `random(min, max)` for a random float or `random_int(min, max)` for a random integer:

```xml
<move x="random(0, 800)" y="random(0, 600)" />
<wait seconds="random(0.5, 2.0)" />
<set var="roll" value="random_int(1, 6)" />
```

### Property Paths

Variable tokens can reference object properties with dot notation. `Vector2` and `Vector3` components (`.x`, `.y`, `.z`) are supported:

```xml
<move x="$target.global_position.x" y="$target.global_position.y" />
```

### Conditional Jumps

`goto_if` compares two values and jumps if the condition is true.

Operators: `eq`, `!=`, `<`, `>`, `<=`, `>=`, `mod` (true when `a % b == 0`).

```xml
<goto_if label="done" var="$counter" op=">=" value="5" />
```

### Calling Methods

`call` targets `"target"` (parent) by default. Use `"self"` for the runner, or a path from `/root/`. Resolved targets are cached for the duration of the run.

Arguments are resolved like any token (`$var`, `random(...)`, `random_int(...)`), then a string that reads as a number becomes one: `"6"` is passed as the int `6`, `"0.5"` as the float `0.5`, so methods with typed parameters (`func take_damage(n: int)`) can be called. Any other string is passed as it is.

```xml
<call method="queue_free" />
<call on="target" method="set_health" arg0="100" />
<call on="target" method="take_damage" arg0="$damage" />
<call on="Game/UI/HUD" method="show_message" arg0="Hello!" />
```

### Waiting for Signals

`wait_signal` pauses the sequence until an object emits a signal, so a sequence can wait for the game (a `call` followed by a `wait` cannot). `on` is resolved like `call`'s (`target` by default, `self`, or a path from `/root/`). If the object or the signal does not exist, it prints an error and the sequence carries on without waiting.

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
        var x := float(resolve_value(x_token))
        var y := float(resolve_value(y_token))
        target.scale = Vector2(x, y)
        return null
```

**2. Factory function** — maps XML attributes to command arguments (the second argument is the command's index in the compiled sequence):

```gdscript
func factory_scale(args: Dictionary, _index: int) -> Callable:
    return cmd_scale(str(args.get("x", "1")), str(args.get("y", "1")))
```

**3. Register** in `register_commands()`:

```gdscript
command_factories["scale"] = factory_scale
```

Then use it: `<scale x="2" y="2" />`

For project-specific commands, subclass and call `super.register_commands()` to keep the built-ins:

```gdscript
class_name MySequenceRunner
extends sequence_runner

func register_commands() -> void:
    super.register_commands()
    command_factories["scale"] = factory_scale
```

## Architecture

The pipeline is **Parse → Compile → Run**. XML is parsed into dictionaries, compiled into an `Array[Callable]` via factory functions, then executed sequentially. Labels are pre-scanned during compilation and stored separately from the command array as index pointers. Parsed XML, label maps, and trigger configs are all statically cached so multiple runners sharing a file do no redundant work. Runtime state lives in a per-run `scratch_pad` dictionary that resets on each `start()` call (then takes the `vars` passed to it). Resolved targets (from `call`) are also cached in the scratch pad to avoid repeated lookups.
