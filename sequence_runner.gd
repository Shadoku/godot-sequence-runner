class_name sequence_runner
extends Node
## Parsed files: path -> {section name -> its commands}, the unnamed section under "".
static var xml_cache: Dictionary = {}
static var trigger_cache: Dictionary = {}
## Label maps: path -> {section name -> {label -> command index}}.
static var label_cache: Dictionary = {}
## Compile errors found reading a file (a duplicate section...): path -> its errors.
static var problem_cache: Dictionary = {}

# Reusable sequence runner. Attach to a node, set xml_path, call start().

## The XML sequence file start() runs when it is given no path.
@export_file("*.xml") var xml_path: String = ""
## Start the sequence on _ready.
@export var auto_start: bool = false
## Drive the runner node itself instead of its parent.
@export var target_self: bool = false
## Print what the runner does (its target, each goto's jump, each <run>) for
## debugging.
@export var verbose: bool = false
## Stop the sequence at its first run-time error (run_error()) and set `failed`.
## Off: a run-time error is reported and the sequence goes on.
@export var stop_on_error: bool = false
## The most commands a sequence may run without waiting (an async command)
## before it is stopped with an error and `failed`, whatever stop_on_error
## says. A loop that never waits would hang the game. The count restarts each
## time the sequence waits. 0: no limit.
@export var max_instant_steps: int = 100000

var target: Node = null
var sequence: Array[Callable] = []
## The section of xml_path the runner runs ("": the unnamed one).
var current_section: String = ""
## The running section's labels: name -> command index.
var labels: Dictionary = {}
var running: bool = false
var index: int = 0
var scratch_pad: Dictionary = {}
## Command name -> its factory, `factory(args: Dictionary, index: int) -> Callable`.
## Filled by register_command(). A factory put here directly still works, its
## attributes unchecked.
var command_factories: Dictionary = {}
## Command name -> the attributes it accepts (register_command()).
var command_attributes: Dictionary = {}
## How many compile errors the last compile found (an unknown command or
## attribute, a goto to a missing label...), start()'s or validate()'s.
var compile_errors: int = 0
## The generator random() and random_int() draw from; null: the global one.
## A seeded generator makes the sequence's randomness reproducible.
var rng: RandomNumberGenerator = null
var trigger_config: Dictionary = {}
## What `<say>` and `<log>` show their text through: any object with the
## methods `say(speaker: String, text: String)` and `log(text: String)` (see
## factory_say() and factory_log()). Null, or a method it lacks: the text is
## printed. A `<run>` child has its parent's.
var presenter: Object = null

## Whether the last sequence was cut by stop() rather than run to its end.
var stopped: bool = false
## Whether the last sequence was stopped by a run-time error (with
## stop_on_error on) or by max_instant_steps. start() clears it.
var failed: bool = false

var _commands_registered: bool = false
# Bumped by every run_sequence() and stop(), so a command's signal from an old
# run does not resume the loop.
var _run_id: int = 0
# The running tween_move's tween, killed by stop().
var _tween: Tween = null
# While validate() runs: compile errors are collected, not pushed.
var _quiet: bool = false
# The file and section being compiled, and the compile errors found, for
# compile_error().
var _compile_path: String = ""
var _compile_section: String = ""
var _compile_problems: PackedStringArray = PackedStringArray()

signal sequence_finished
# What the loop waits on during an async command (run_sequence()).
signal _resumed

## The `$` references of an expression: a variable or a path (`$a`, `$piece.props.health`);
## a segment followed by `(` is left to the Expression (a method call on what was read).
static var _reference_regex: RegEx = null
# What an expression calls its functions on (ExprScope), made on first use.
var _expr_scope: ExprScope = null

## An expression (the `expr` of set, set_prop or if) as compile_expr() builds
## it: its `$` references replaced by input names and parsed once, by Godot's
## Expression. run_expr() resolves the references and executes it.
class CompiledExpr extends RefCounted:
	## The expression as written.
	var text: String = ""
	## The references it reads, without their `$`, in input order.
	var paths: PackedStringArray = PackedStringArray()
	## The parsed Expression (over `text` with each reference an input).
	var expression: Expression = Expression.new()
	## Whether it parsed; `error` says why not.
	var ok: bool = false
	var error: String = ""

## What an expression may call besides Godot's built-in functions: random(min,
## max) and random_int(min, max), on the runner's rng. A bare name is an error.
class ExprScope extends RefCounted:
	# An Expression reads a bare name as a member of this scope, so no member
	# holds the runner. A lambda made here answers get_object() with the scope,
	# not with the runner it captured.
	var _draw_float: Callable
	var _draw_int: Callable

	func _init(owner: sequence_runner) -> void:
		_draw_float = func(min_value: float, max_value: float) -> float:
			return owner.random(min_value, max_value)
		_draw_int = func(min_value: int, max_value: int) -> int:
			return owner.random_int(min_value, max_value)

	func random(min_value: float, max_value: float) -> float:
		return _draw_float.call(min_value, max_value)

	func random_int(min_value: int, max_value: int) -> int:
		return _draw_int.call(min_value, max_value)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _commands_registered:
		register_commands()
	if target == null:
		if verbose:
			print("Targeting parent")
		target = get_parent()
	if target_self == true:	
		if verbose:
			print("Targeting self")
		target = self
	if auto_start == true && xml_path != "":
		start()

## Runs the section `section` ("": the unnamed <sequence>) of the file at `path`
## (or xml_path). `vars` seed the scratch pad after its reset, so the sequence
## can read them as `$name`. Returns false, with an error, when the file has no
## such section or cannot be read: nothing runs and sequence_finished is not
## emitted.
func start(path: String = "", vars: Dictionary = {}, section: String = "") -> bool:
	return _start_section(path, vars, section, true)

# start()'s work. `use_trigger` false runs the section at once whatever the
# file's <trigger> says (<run> and run_once()).
func _start_section(path: String, vars: Dictionary, section: String, use_trigger: bool) -> bool:
	if not _commands_registered:
		register_commands()
	xml_path = path if path != "" else xml_path
	if xml_path == "":
		push_error("sequence_runner: no XML file set (xml_path is empty)")
		return false
	var parsed := parse_xml(xml_path)
	if not parsed.has(section):
		if xml_cache.has(xml_path):
			push_error("sequence_runner: %s has no section \"%s\"" % [xml_path, section])
		return false
	index = 0
	stopped = false
	failed = false
	current_section = section
	scratch_pad = {}
	scratch_pad.merge(vars)
	_for_each_states = {}
	_gosub_stack = []
	var commands: Array[Dictionary] = parsed[section]
	labels = label_map(commands)
	if not label_cache.has(xml_path):
		label_cache[xml_path] = {}
	label_cache[xml_path][section] = labels
	_compile_path = xml_path
	_compile_section = section
	_compile_problems = PackedStringArray()
	sequence = compile_sequence(commands)
	if use_trigger and trigger_config.size() > 0:
		setup_trigger()
	else:
		run_sequence(sequence)
	return true

## A coroutine: calls start() with the same arguments, then waits for
## sequence_finished only if the sequence still runs, so
## `await runner.start_and_wait(...)` never hangs on a section of instant
## commands (it finishes inside start()). Returns false at once when start()
## does (no such section, no file), true once the sequence has finished or was
## stopped. A file whose <trigger> defers the start (signal, timer) is not
## waited for. It returns true at once and the sequence runs later.
func start_and_wait(path: String = "", vars: Dictionary = {}, section: String = "") -> bool:
	if not start(path, vars, section):
		return false
	if running:
		await sequence_finished
	return true

## How deep `<run>` may nest sub-sequences (a section that runs itself...). The
## runner a game starts is depth 0, its `<run>` child depth 1, and so on. A
## `<run>` that would go deeper is a run-time error and runs nothing.
const MAX_RUN_DEPTH: int = 32

## A coroutine: runs the section `section` of the file at `path` on a
## temporary runner (an instance of `runner_script`, a sequence_runner script;
## null: sequence_runner) added as a child of `host`, which it targets. `vars`
## seed its scratch pad, as start()'s do. The file's <trigger> is ignored: the
## section runs at once. Waits until it ends, frees the runner and returns
## true when it ran to its end (a <stop/> counts), false when the section is
## missing, it `failed`, or `host` was freed or left the tree meanwhile (the
## runner is stopped; this then returns a frame later, outside the freeing).
## One runner per call lets several sections run side by side.
static func run_once(host: Node, path: String, vars: Dictionary = {}, section: String = "", runner_script: Script = null) -> bool:
	if not is_instance_valid(host):
		push_error("sequence_runner: run_once: no host")
		return false
	var made: Variant = runner_script.new() if runner_script != null else sequence_runner.new()
	var runner := made as sequence_runner
	if runner == null:
		push_error("sequence_runner: run_once: %s is not a sequence_runner script" % runner_script.resource_path)
		if made is Object and not made is RefCounted:
			(made as Object).free()
		return false
	runner.target = host
	host.add_child(runner)
	var tree: SceneTree = runner.get_tree() if runner.is_inside_tree() else null
	var host_gone: Array[bool] = [false]
	runner.tree_exiting.connect(func() -> void:
		host_gone[0] = true
		runner.stop())
	if not runner._start_section(path, vars, section, false):
		runner.free()
		return false
	if not runner.running:
		var instant_ok := not runner.failed
		runner.free()
		return instant_ok
	await runner.sequence_finished
	if host_gone[0]:
		# Resumed from inside the host's freeing (or removal): return outside it.
		if tree != null:
			await tree.process_frame
		if is_instance_valid(runner):
			runner.free()
		return false
	var ok := not runner.failed
	# Resumed while the runner emits sequence_finished: free it once that ends.
	runner.queue_free()
	return ok

## Adds a runner for `xml` to `node`. `auto` starts it there with start()'s
## `vars` and `section`. Example:
## `sequence_runner.attach($node, "res://data/sequences/whatever.xml")`
static func attach(node: Node, xml: String, auto: bool = false, vars: Dictionary = {}, section: String = "") -> sequence_runner:
	var runner := sequence_runner.new()
	runner.xml_path = xml
	node.add_child(runner)
	if auto:
		runner.start("", vars, section)
	return runner

## The section names of the file at `path`, in file order ("" for its unnamed
## <sequence>). Empty, with an error, for a file that cannot be read.
static func sections(path: String) -> PackedStringArray:
	return PackedStringArray(read_sections(path).keys())

## Whether the file at `path` has the section `section_name` ("": the unnamed one).
static func has_section(path: String, section_name: String) -> bool:
	return read_sections(path).has(section_name)
	
## Registers the built-in commands (start() and validate() call it when _ready()
## has not run yet). A subclass adds its own after `super.register_commands()`.
func register_commands() -> void:
	command_factories = {}
	command_attributes = {}
	_commands_registered = true
	register_command("move", factory_move, PackedStringArray(["x", "y"]))
	register_command("wait", factory_wait, PackedStringArray(["seconds"]))
	register_command("goto", factory_goto, PackedStringArray(["label"]))
	register_command("play_anim", factory_play_anim, PackedStringArray(["anim", "node_path"]))
	register_command("call", factory_call, PackedStringArray(["on", "method", "var", "await", "arg*"]))
	register_command("pause", factory_pause, PackedStringArray(["time"]))
	register_command("unpause", factory_unpause, PackedStringArray())
	register_command("set", factory_set, PackedStringArray(["var", "value", "expr"]))
	register_command("goto_if", factory_goto_if, PackedStringArray(["label", "var", "op", "value"]))
	register_command("tween_move", factory_tween_move, PackedStringArray(["x", "y", "duration"]))
	register_command("wait_signal", factory_wait_signal, PackedStringArray(["on", "signal"]))
	register_command("set_prop", factory_set_prop, PackedStringArray(["on", "prop", "value", "expr"]))
	register_command("if", factory_if_block, PackedStringArray(["expr"]))
	register_command("else", factory_else_block, PackedStringArray())
	register_command("for_each", factory_for_each_block, PackedStringArray(["var", "in", "index"]))
	register_command("stop", factory_stop, PackedStringArray())
	register_command("run", factory_run_section, PackedStringArray(["section", "file", "var"]))
	register_command("gosub", factory_gosub, PackedStringArray(["label"]))
	register_command("return", factory_return, PackedStringArray())
	register_command("choose", factory_choose, PackedStringArray([OPTIONS_ARG]))
	register_command("call_return", factory_call_return, PackedStringArray(["on", "method", "var", "await", "arg*"]))
	register_command("end", factory_end, PackedStringArray())
	register_command("say", factory_say, PackedStringArray(["text", "speaker"]))
	register_command("log", factory_log, PackedStringArray(["text"]))

## Registers the command `cmd_name`. `factory(args: Dictionary, index: int) ->
## Callable` builds it from the command's attributes, and `attributes` are the
## ones it accepts (an entry ending in `*` stands for that prefix followed by
## digits: call's `arg*` takes arg0, arg1...). Any other attribute is a compile
## error.
func register_command(cmd_name: String, factory: Callable, attributes: PackedStringArray) -> void:
	command_factories[cmd_name] = factory
	command_attributes[cmd_name] = attributes

## Whether `attribute` is one of `accepted` (register_command()'s list).
static func accepts_attribute(accepted: PackedStringArray, attribute: String) -> bool:
	if accepted.has(attribute):
		return true
	for entry: String in accepted:
		if entry.ends_with("*"):
			var rest := attribute.trim_prefix(entry.trim_suffix("*"))
			if attribute.begins_with(entry.trim_suffix("*")) and rest != "" and rest.lstrip("0123456789") == "":
				return true
	return false

## Compiles every section of the file at `path` without running anything or
## pushing an error, and returns one line per compile error: `<file>:<section>:
## <error>` (an unknown command, an unknown attribute of a known command, a
## goto or goto_if to a label the section lacks, what a factory reported) and
## `<file>: <error>` for the file itself (it cannot be read, it has no
## section, two sections share a name). Empty when the file is sound. The
## runner's own commands count (a subclass's included), registered first when
## _ready() has not run, so a runner outside the tree can validate.
func validate(path: String) -> PackedStringArray:
	if not _commands_registered:
		register_commands()
	var problems := PackedStringArray()
	var parsed := read_sections(path, true)
	if not xml_cache.has(path):
		problems.append("%s: cannot be read" % path)
		compile_errors = problems.size()
		return problems
	for problem: String in problem_cache.get(path, PackedStringArray()):
		problems.append("%s: %s" % [path, problem])
	var was_quiet := _quiet
	_quiet = true
	for section_name: String in parsed:
		_compile_path = path
		_compile_section = section_name
		_compile_problems = PackedStringArray()
		compile_sequence(parsed[section_name])
		problems.append_array(_compile_problems)
	_quiet = was_quiet
	compile_errors = problems.size()
	return problems

## Reports a compile error (a factory calls it for a bad attribute value). It
## is counted in compile_errors and pushed as an error unless validate() is
## collecting.
func compile_error(message: String) -> void:
	compile_errors += 1
	var line := "%s:%s: %s" % [_compile_path, _compile_section, message]
	_compile_problems.append(line)
	if not _quiet:
		push_error("sequence_runner: " + line)

## A section's labels: label name -> the index of its (no-op) command.
static func label_map(parsed: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for i: int in range(parsed.size()):
		var cmd: Dictionary = parsed[i]
		if cmd.get("name", "") == "label":
			result[cmd["args"].get("name", "")] = i
	return result

## Compiles a section's commands into callables, each through its registered
## factory (a label is a no-op, so indices match the commands'). Blocks are
## paired first (an <if> with its <else/> and end marker, a <for_each> with its
## end marker), so their factories know where to jump. A block's end marker
## compiles to its loop-back or a no-op. Compile errors (an unknown command or
## attribute, a goto or goto_if to a label the section lacks, an <else/>
## outside an <if>) go through compile_error() and are counted in
## compile_errors. An unknown command compiles to a no-op.
func compile_sequence(parsed: Array[Dictionary]) -> Array[Callable]:
	compile_errors = 0
	var section_labels := label_map(parsed)
	var result : Array[Callable] = []
	var blocks := _pair_blocks(parsed)
	_block_links = blocks["links"]
	var block_problems: Dictionary = blocks["problems"]

	for cmd: Dictionary in parsed:
		var cmd_name: String = cmd.get("name", "")
		var args: Dictionary = cmd.get("args", {})
		for problem: String in block_problems.get(result.size(), PackedStringArray()):
			compile_error(problem)
		if _BLOCK_ENDS.values().has(cmd_name) and not command_factories.has(cmd_name):
			result.append(_compile_block_end(result.size()))
			continue
		if cmd_name == "label":
			check_attributes(cmd_name, args, PackedStringArray(["name"]))
			result.append(func() -> Variant: return null)
			continue
		if not command_factories.has(cmd_name):
			compile_error("unknown command <%s>" % cmd_name)
			result.append(func() -> Variant: return null)
			continue
		if command_attributes.has(cmd_name):
			check_attributes(cmd_name, args, command_attributes[cmd_name])
		if (cmd_name == "goto" or cmd_name == "goto_if" or cmd_name == "gosub") and not section_labels.has(str(args.get("label", ""))):
			compile_error("<%s> to a label the section lacks: \"%s\"" % [cmd_name, args.get("label", "")])
		if args.get(OPTIONS_ARG) is Array:
			for option: Dictionary in args[OPTIONS_ARG]:
				if not section_labels.has(str(option.get("goto", ""))):
					compile_error("<%s>: an <option> goes to a label the section lacks: \"%s\"" % [cmd_name, option.get("goto", "")])
		var factory: Callable = command_factories[cmd_name]
		result.append(factory.call(args, result.size()))
	return result

## Reports a run-time error (an unresolvable reference, a missing object,
## method, signal or key, a bad operand...) as an error naming the file and
## section. The sequence goes on, unless stop_on_error is on: then `failed`
## turns true and the sequence stops (stop()), and the built-in command that met
## the error does nothing more (it checks `failed` before acting).
func run_error(message: String) -> void:
	push_error("sequence_runner: %s:%s: %s" % [xml_path, current_section, message])
	if stop_on_error:
		failed = true
		stop()

## Reports, through compile_error(), each attribute of `args` that `accepted`
## (register_command()'s list for `cmd_name`) does not hold.
func check_attributes(cmd_name: String, args: Dictionary, accepted: PackedStringArray) -> void:
	for attribute: String in args:
		if not accepts_attribute(accepted, attribute):
			compile_error("<%s> has no attribute \"%s\"" % [cmd_name, attribute])
		
	
func cmd_move(x_token: String, y_token: String) -> Callable:
	return func() -> Variant:
		if target:
			var x := to_float(resolve_value(x_token))
			var y := to_float(resolve_value(y_token))
			if failed:
				return null
			target.global_position = Vector2(x, y)
		return null
	
func cmd_wait(time_token: String = "0") -> Callable:
	return func() -> Variant:
		var time := to_float(resolve_value(time_token))
		if failed:
			return null
		return get_tree().create_timer(time).timeout
		
## Pauses the scene tree. A `time_token` above 0 unpauses it after that many
## seconds and the sequence waits for it. An empty one (`<pause />` without
## `time`) leaves the tree paused until an `<unpause />`. A time of 0 or less
## pauses too and is a run-time error.
func cmd_pause(time_token: String = "0.016") -> Callable:
	return func() -> Variant:
		var time := to_float(resolve_value(time_token))
		if failed:
			return null
		get_tree().paused = true
		if time > 0:
			var timer := get_tree().create_timer(time, true, false, false)
			timer.timeout.connect(func() -> void: get_tree().paused = false)
			return timer.timeout
		if time_token != "":
			run_error("pause: time is %s; set it above 0, or leave it out to pause until <unpause />" % time)
		return null
		
func cmd_unpause() -> Callable:
	return func() -> Variant:
		get_tree().paused = false
		return null
		
func cmd_goto(label: String) -> Callable:
	return func() -> Variant:
		if verbose:
			print("Jumping to: ", label)
		jump(label)
		return null

## Moves the running section to its label `label` (an error when it has none).
func jump(label: String) -> void:
	if labels.has(label):
		index = labels[label]
		_leave_for_each_loops(index)
	else:
		run_error("no label \"%s\" in the section" % label)

func cmd_play_anim(anim: String, node_path: String = "") -> Callable:
	return func() -> Variant:
		var anim_target: AnimatedSprite2D
		if target is AnimatedSprite2D:
			anim_target = target as AnimatedSprite2D
		elif node_path != "":
			if not scratch_pad.has("anim_target_" + node_path):
				anim_target = target.get_node_or_null(node_path) as AnimatedSprite2D
				scratch_pad["anim_target_" + node_path] = anim_target
			else: 
				anim_target = scratch_pad["anim_target_" + node_path]
		else:
			if not scratch_pad.has("anim_target"):
				anim_target = find_animated_sprite(target)
				scratch_pad["anim_target"] = anim_target
			else:
				anim_target = scratch_pad["anim_target"]
		if anim_target:
			anim_target.play(anim)
		else:
			run_error("play_anim: no AnimatedSprite2D found")
		return null
		
func find_animated_sprite(node: Node) -> AnimatedSprite2D:
	for child: Node in node.get_children():
		if child is AnimatedSprite2D:
			return child as AnimatedSprite2D
		var result := find_animated_sprite(child)
		if result:
			return result
	return null
		
## Calls `method` on what `on` names with the resolved arguments. `var_name`
## (when not empty) stores the return value in the scratch pad. `awaited` makes
## the command async when the method returns a Signal (the sequence waits for
## it) or is a coroutine (it waits for the method to finish, and `var_name` gets
## its final return value); any other return value goes on at once.
func cmd_call(on: String, method: String, args_tokens: Array, var_name: String = "", awaited: bool = false) -> Callable:
	return func() -> Variant:
		var target_node: Object = resolve_target(on)
		var resolved_args: Array = []
		for token: Variant in args_tokens:
			if token is String:
				resolved_args.append(to_value(resolve_value(token)))
			else:
				resolved_args.append(token)
		if failed:
			return null
		if target_node == null or not target_node.has_method(method):
			run_error("call: no object \"%s\", or it has no method \"%s\"" % [on, method])
			return null
		var result: Variant = target_node.callv(method, resolved_args)
		var coroutine := is_coroutine(result)
		if var_name != "":
			scratch_pad[var_name] = null if coroutine else result
		if not awaited:
			return null
		if result is Signal:
			return result
		if coroutine:
			var state: Object = result
			if var_name != "":
				state.connect("completed", func(value: Variant) -> void: scratch_pad[var_name] = value, CONNECT_ONE_SHOT)
			return Signal(state, "completed")
		return null

## Whether `value` is what calling a method that awaits returns before it ends
## (a GDScriptFunctionState, whose `completed` signal carries the return value).
static func is_coroutine(value: Variant) -> bool:
	return typeof(value) == TYPE_OBJECT and is_instance_valid(value) and (value as Object).get_class() == "GDScriptFunctionState"
		
## Waits for `signal_name` on the object `on` names (resolved like call's `on`).
func cmd_wait_signal(on: String, signal_name: String) -> Callable:
	return func() -> Variant:
		var source: Object = resolve_target(on)
		if failed:
			return null
		if source and source.has_signal(signal_name):
			return Signal(source, signal_name)
		run_error("wait_signal: no object \"%s\", or it has no signal \"%s\"" % [on, signal_name])
		return null
		
## Sets the variable `var_name` to `value` resolved as a token and typed
## (to_value()), or to `expr` evaluated (an expression, compiled now: a syntax
## error is a compile error and the command then does nothing).
func cmd_set(var_name: String, value: Variant, expr: String) -> Callable:
	var compiled := compile_command_expr("set", expr)
	return func() -> Variant:
		if compiled != null:
			if compiled.ok:
				var result: Variant = run_expr(compiled)
				if failed:
					return null
				scratch_pad[var_name] = result
		else:
			var typed: Variant = to_value(resolve_value(value)) if value is String else value
			if failed:
				return null
			scratch_pad[var_name] = typed
		return null
			
## Writes at the path `prop` of what `on` names (an object as call's `on`
## resolves it, or a variable holding a dictionary; path_root()): `value`
## resolved as a token, or `expr` evaluated as set's.
func cmd_set_prop(on: String, prop: String, value_token: String, expr: String) -> Callable:
	var compiled := compile_command_expr("set_prop", expr)
	return func() -> Variant:
		if compiled != null and not compiled.ok:
			return null
		var root: Variant = path_root(on)
		if failed:
			return null
		if root == null:
			run_error("set_prop: no object \"%s\"" % on)
			return null
		var value: Variant = run_expr(compiled) if compiled != null else to_value(resolve_value(value_token))
		if failed:
			return null
		write_property_path(root, prop, value)
		return null

## Word aliases of goto_if's comparison operators. A bare `<` in an attribute
## is not valid XML, so `op="lt"` reads as `op="<"`, and so on.
const GOTO_IF_OP_ALIASES := {"lt": "<", "gt": ">", "le": "<=", "ge": ">="}

## Jumps to `label` when `var_token` compared by `op` with `value_token` holds.
## `op` is `eq`, `!=`, `<`, `>`, `<=`, `>=`, `mod`, or one of the aliases
## `lt`, `gt`, `le`, `ge` (GOTO_IF_OP_ALIASES). Each operand is a variable's
## name or a token, typed by to_value(). When either is a string that does not
## read as a number, `eq` and `!=` compare the two as strings and the other
## operators (the aliases too) are an error; otherwise both compare as numbers
## (a bool as 0 or 1). An operand that cannot be resolved, or an unknown
## operator, is an error, and nothing jumps.
func cmd_goto_if(label: String, var_token: String, op_name: String, value_token: String) -> Callable:
	var op: String = GOTO_IF_OP_ALIASES.get(op_name, op_name)
	return func() -> Variant:
		var a: Variant = goto_if_operand(var_token)
		if a == null:
			run_error("goto_if: cannot resolve the first operand: " + var_token)
			return null
		var b: Variant = goto_if_operand(value_token)
		if b == null:
			run_error("goto_if: cannot resolve the second operand: " + value_token)
			return null
		if failed:
			return null
		var result := false
		if a is String or b is String:
			match op:
				"eq":
					result = str(a) == str(b)
				"!=":
					result = str(a) != str(b)
				_:
					run_error("goto_if: \"%s\" compares numbers, not the strings %s and %s" % [op_name, var_token, value_token])
					return null
		else:
			var x := to_float(a)
			var y := to_float(b)
			match op:
				"eq":
					result = x == y
				"!=":
					result = x != y
				"<":
					result = x < y
				">":
					result = x > y
				"<=":
					result = x <= y
				">=":
					result = x >= y
				"mod":
					result = !fmod(x, y)
				_:
					run_error("goto_if: unknown operator: " + op_name)
		if result:
			jump(label)
		return null

## A goto_if operand's value: the variable named `token`, else the token
## resolved; typed by to_value().
func goto_if_operand(token: String) -> Variant:
	return to_value(scratch_pad[token] if scratch_pad.has(token) else resolve_value(token))
	
func cmd_tween_move(x_token: String, y_token: String, dur_token: String) -> Callable:
	return func() -> Variant:
		var pos := Vector2(to_float(resolve_value(x_token)), to_float(resolve_value(y_token)))
		var duration := to_float(resolve_value(dur_token))
		if failed:
			return null
		var tween := create_tween()
		tween.tween_property(target, "global_position", pos, duration)
		_tween = tween
		return tween.finished

## Ends the running sequence. No further command runs (one waiting is
## abandoned, a tween_move's tween killed, a running `<run>` child stopped and
## freed), `running` turns false, `stopped` true, and sequence_finished is
## emitted at once, as at the end, so a host waiting on it never hangs. Does
## nothing when no sequence is running.
func stop() -> void:
	if not running:
		return
	running = false
	stopped = true
	_run_id += 1
	for child: sequence_runner in _run_children.duplicate():
		if is_instance_valid(child):
			child.stop()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_resumed.emit()
	sequence_finished.emit()
		
## Runs `commands` from `index` as one coroutine: an instant command (it
## returns null) goes straight on, an async one (it returns a Signal) is waited
## for. The loop waits on the runner's own `_resumed`, which the command's
## signal triggers for this run only, so stop() can end a waiting run at once
## and a signal left over from a stopped run never resumes a later one.
func run_sequence(commands: Array[Callable]) -> void:
	if running:
		return
	running = true
	sequence = commands
	_run_id += 1
	var run_id := _run_id
	# Commands run since the loop last waited (max_instant_steps).
	var instant_steps: int = 0

	while running && index < sequence.size():
		if max_instant_steps > 0 and instant_steps >= max_instant_steps:
			push_error("sequence_runner: %s:%s: more than %d commands without waiting (max_instant_steps); the sequence is stopped" % [xml_path, current_section, max_instant_steps])
			failed = true
			stop()
			return
		instant_steps += 1
		var current: Callable = sequence[index]
		index = index + 1

		if current.is_valid():
			var result: Variant = current.call()
			if run_id != _run_id:
				return
			if result is Signal:
				var awaited: Signal = result
				var resume := _on_command_done.bind(run_id)
				var arity := signal_arity(awaited)
				awaited.connect(resume.unbind(arity) if arity > 0 else resume, CONNECT_ONE_SHOT)
				await _resumed
				if run_id != _run_id:
					return
				instant_steps = 0
		else:
			run_error("invalid command at %d" % (index - 1))

	running = false
	_tween = null
	sequence_finished.emit()

# An async command's signal fired: resumes the loop if its run is the current one.
func _on_command_done(run_id: int) -> void:
	if run_id == _run_id:
		_resumed.emit()

## How many arguments `sig` passes (as declared), so the loop can listen to any
## signal.
static func signal_arity(sig: Signal) -> int:
	var source := sig.get_object()
	if source == null:
		return 0
	for info: Dictionary in source.get_signal_list():
		if info["name"] == sig.get_name():
			return (info["args"] as Array).size()
	return 0
	
## The sections of the file at `path` (read_sections()) and its <trigger> as
## trigger_config.
func parse_xml(path: String) -> Dictionary:
	var parsed := read_sections(path)
	trigger_config = trigger_cache.get(path, {})
	return parsed

## Reads the file at `path` once (cached): section name -> its commands
## ({"name": command, "args": {attribute: value}}), the unnamed <sequence> under
## "", in file order, flat (a nested element is the next command). An <if> or a
## <for_each> is followed, where it ends, by an end marker (`end_if`,
## `end_for_each`, no attributes). The <option> elements inside a <choose> are
## not commands: their attributes are listed, in order, under OPTIONS_ARG in
## the <choose>'s "args" (any other element in there is dropped as a compile
## error). Its <trigger> goes to trigger_cache. A second
## section of the same name is dropped as a compile error (problem_cache). Empty
## for a file that cannot be read: an error unless `quiet`.
static func read_sections(path: String, quiet: bool = false) -> Dictionary:
	if xml_cache.has(path):
		return xml_cache[path]
	var parser := XMLParser.new()
	var result: Dictionary = {}
	var valid := parser.open(path) if FileAccess.file_exists(path) else ERR_FILE_NOT_FOUND
	if valid != OK:
		if not quiet:
			push_error("sequence_runner: %s: cannot be read" % path)
		return result
	var problems := PackedStringArray()
	var commands: Array[Dictionary] = []
	var found_sequence := false
	# The <choose> being read ("": none) and its options so far.
	var option_parent: String = ""
	var options: Array[Dictionary] = []
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT:
			var node_name := parser.get_node_name()

			if node_name == "trigger":
				var config: Dictionary = {}
				for arg: int in range(parser.get_attribute_count()):
					config[parser.get_attribute_name(arg)] = parser.get_attribute_value(arg)
				trigger_cache[path] = config
				var trigger_type: String = config.get("type", "manual")
				if not TRIGGER_TYPES.has(trigger_type):
					problems.append("trigger type \"%s\" is not one of %s" % [trigger_type, ", ".join(TRIGGER_TYPES)])
				continue

			if node_name == "sequence":
				var section_name := parser.get_named_attribute_value_safe("name")
				commands = []
				if result.has(section_name):
					problems.append("a second section \"%s\" (ignored)" % section_name)
				else:
					result[section_name] = commands
				found_sequence = not parser.is_empty()
				continue
			if found_sequence:
				var arguments: Dictionary = {}
				for arg: int in range(parser.get_attribute_count()):
					arguments[parser.get_attribute_name(arg)] = parser.get_attribute_value(arg)

				if option_parent != "":
					if node_name == "option":
						options.append(arguments)
					else:
						problems.append("<%s> inside a <%s> (ignored): only <option> belongs there" % [node_name, option_parent])
					continue
				if OPTION_PARENTS.has(node_name):
					options = []
					arguments[OPTIONS_ARG] = options
					if not parser.is_empty():
						option_parent = node_name
				commands.append({
					"name": node_name,
					"args": arguments
					})
				if _BLOCK_ENDS.has(node_name) and parser.is_empty():
					commands.append({"name": _BLOCK_ENDS[node_name], "args": {}})
		elif parser.get_node_type() == XMLParser.NODE_ELEMENT_END:
			if parser.get_node_name() == "sequence":
				found_sequence = false
				option_parent = ""
			elif parser.get_node_name() == option_parent:
				option_parent = ""
			elif found_sequence and _BLOCK_ENDS.has(parser.get_node_name()):
				commands.append({"name": _BLOCK_ENDS[parser.get_node_name()], "args": {}})
	if result.is_empty():
		problems.append("no section (no <sequence> element)")
	xml_cache[path] = result
	problem_cache[path] = problems
	if not quiet:
		for problem: String in problems:
			push_error("sequence_runner: %s: %s" % [path, problem])
	return result
				
				 
## The values a <trigger>'s `type` may have. Any other is an error: validate()
## lists it, and start() reports it and runs nothing.
const TRIGGER_TYPES: PackedStringArray = ["auto", "manual", "signal", "timer"]

func setup_trigger() -> void:
	var type: String = trigger_config.get("type", "manual")
	
	match type:
		"signal":
			var source_path: String = trigger_config.get("source", "")
			var signal_name: String = trigger_config.get("signal", "")
			var source_node := target.get_node_or_null(source_path)
			if source_node && source_node.has_signal(signal_name):
				source_node. connect(signal_name, _on_trigger_signal)
			else:
				run_error("trigger: no node \"%s\", or it has no signal \"%s\"" % [source_path, signal_name])
		"timer":
			var seconds := float(trigger_config.get("seconds", "1.0"))
			var timer := Timer.new()
			timer.one_shot = true
			timer.wait_time = seconds
			add_child(timer)
			timer.timeout.connect(_on_trigger_timer.bind(timer))
			timer.start()
		"auto", "manual":
			run_sequence(sequence)
		_:
			run_error("trigger: type \"%s\" is not one of %s; nothing runs" % [type, ", ".join(TRIGGER_TYPES)])
				
func _on_trigger_signal(body: Node = null) -> void:
	var filter_group: String = trigger_config.get("filter_group", "")
	if filter_group != "" && body is Node:
		if not body.is_in_group(filter_group):
			return
	if not running:
		run_sequence(sequence)
		
func _on_trigger_timer(timer: Timer) -> void:
	timer.queue_free()
	if not running:
		run_sequence(sequence)

## The regex of an expression's `$` references (see _reference_regex).
static func reference_regex() -> RegEx:
	if _reference_regex == null:
		_reference_regex = RegEx.new()
		_reference_regex.compile("\\$(\\w+(?:\\.(?!\\w+\\()\\w+)*)")
	return _reference_regex

## Compiles the expression `text`: every `$` reference (a variable or a path, as
## any token reads one) becomes an input of a Godot Expression, parsed once.
## `ok` is false, with `error`, when the text does not parse. Expression sees
## syntax only: an unknown function or member shows when it runs.
static func compile_expr(text: String) -> CompiledExpr:
	var compiled := CompiledExpr.new()
	compiled.text = text
	var names := PackedStringArray()
	var rewritten := ""
	var last := 0
	for found: RegExMatch in reference_regex().search_all(text):
		var path := found.get_string(1)
		var at := compiled.paths.find(path)
		if at < 0:
			at = compiled.paths.size()
			compiled.paths.append(path)
			names.append("_r%d" % at)
		rewritten += text.substr(last, found.get_start() - last) + names[at]
		last = found.get_end()
	rewritten += text.substr(last)
	if compiled.expression.parse(rewritten, names) == OK:
		compiled.ok = true
	else:
		compiled.error = compiled.expression.get_error_text()
	return compiled

## Compiles a command's `expr` with its section (the factories run then).
## A syntax error is a compile_error() naming the command, listed by
## validate(). Null when `expr` is empty.
func compile_command_expr(cmd_name: String, expr: String) -> CompiledExpr:
	if expr == "":
		return null
	var compiled := compile_expr(expr)
	if not compiled.ok:
		compile_error("<%s> expr \"%s\": %s" % [cmd_name, expr, compiled.error])
	return compiled

## Runs a compiled expression: each reference resolved (resolve_value(), its
## errors as a token's) and typed by expr_input(), then executed against an
## ExprScope. A failure (an unknown function, a member the Expression cannot
## read, `'a' + 1`, an int divided by zero) is an error and reads as 0. So is a
## float result that is not finite (a float divided by zero), so a division by
## zero never passes as inf. The text is never the value.
func run_expr(compiled: CompiledExpr) -> Variant:
	if not compiled.ok:
		run_error("expression \"%s\": %s" % [compiled.text, compiled.error])
		return 0
	var values: Array = []
	for path: String in compiled.paths:
		values.append(expr_input(resolve_value("$" + path)))
	if _expr_scope == null:
		_expr_scope = ExprScope.new(self)
	var result: Variant = compiled.expression.execute(values, _expr_scope, false)
	if compiled.expression.has_execute_failed():
		run_error("expression \"%s\": %s" % [compiled.text, compiled.expression.get_error_text()])
		return 0
	if result is float and not is_finite(result):
		run_error("expression \"%s\" divides by zero or overflows" % compiled.text)
		return 0
	return result

## A reference's value as an expression reads it: typed by to_value() (a string
## that reads as a number is one), then an int, a bool or null as a float, what
## to_float() gives the other commands (`$i + 1` is 2.0, a flag adds as 1, an
## unresolvable reference, already reported, reads as 0); anything else (a
## string, a vector, an object, a dictionary, an array) as it is.
static func expr_input(value: Variant) -> Variant:
	var typed: Variant = to_value(value)
	match typeof(typed):
		TYPE_INT, TYPE_BOOL:
			return float(typed)
		TYPE_NIL:
			return 0.0
	return typed

## Evaluates the expression `text` in one go, for code that has only a string
## (a set's expr is compiled with its section instead). A syntax error is a
## run-time error here.
func evaluate_expr(text: String) -> Variant:
	return run_expr(compile_expr(text))
			
	
## The object `path` names (call's and wait_signal's `on`, the head of a
## property path): `target`, `self`, then a variable of that name holding an
## Object (a `$` prefix is accepted and stripped; an object handed in with
## start()'s vars), then the node at `/root/<path>`, cached for the run as
## `target_<path>` (a variable's object is not cached). Null when none is found.
func resolve_target(path: String) -> Object:
	var key := path.trim_prefix("$")
	match key:
		"target":
			return target
		"self":
			return self
	if scratch_pad.has(key) and typeof(scratch_pad[key]) == TYPE_OBJECT:
		var named: Variant = scratch_pad[key]
		if is_instance_valid(named):
			return named
		run_error("$%s was freed" % key)
		return null
	if scratch_pad.has("target_" + key):
		return scratch_pad["target_" + key]
	var result: Object = get_node_or_null("/root/" + key) if is_inside_tree() else null
	if result != null:
		scratch_pad["target_" + key] = result
	return result
	
	
func resolve_value(token: String) -> Variant:
	if token.begins_with("random("):
		return resolve_random(token)
	if token.begins_with("random_int("):
		return resolve_random_int(token)
	if not token.begins_with("$"):
		return token
	var ref := token.substr(1)
	if scratch_pad.has(ref):
		return scratch_pad[ref]
	return resolve_property_path(ref)
	
## A token's value typed, for call's arguments and set's and set_prop's values:
## a String `true` or `false` (any case) becomes that bool; one wrapped in
## single quotes (`'7'`) is the string inside, whatever it reads as; one that
## reads as an int or a float becomes that number (so methods with typed
## parameters can be called); any other value is returned as it is.
static func to_value(value: Variant) -> Variant:
	if value is String:
		var text: String = value
		if text.length() >= 2 and text.begins_with("'") and text.ends_with("'"):
			return text.substr(1, text.length() - 2)
		var lower := text.to_lower()
		if lower == "true":
			return true
		if lower == "false":
			return false
		if text.is_valid_int():
			return text.to_int()
		if text.is_valid_float():
			return text.to_float()
	return value
	
func resolve_random(token: String) -> float:
	var operands := token.trim_prefix("random(").trim_suffix(")")
	var parts := operands.split(",")
	if parts.size() != 2:
		run_error("expected random(min, max), got: " + token)
		return 0.0
	var min_val := to_float(resolve_value(parts[0].strip_edges()))
	var max_val := to_float(resolve_value(parts[1].strip_edges()))
	return random(min_val, max_val)
	
func resolve_random_int(token: String) -> int:
	var operands := token.trim_prefix("random_int(").trim_suffix(")")
	var parts := operands.split(",")
	if parts.size() != 2:
		run_error("expected random_int(min, max), got: " + token)
		return 0
	var min_val := int(to_float(resolve_value(parts[0].strip_edges())))
	var max_val := int(to_float(resolve_value(parts[1].strip_edges())))
	return random_int(min_val, max_val)

## A random float in [min_value, max_value] from `rng` when one is set (seeded),
## else the global generator: the token `random(min,max)` and the function
## `random(min, max)` inside an expression.
func random(min_value: float, max_value: float) -> float:
	return rng.randf_range(min_value, max_value) if rng != null else randf_range(min_value, max_value)

## A random int in [min_value, max_value], as random(): the token
## `random_int(min,max)` and the function inside an expression.
func random_int(min_value: int, max_value: int) -> int:
	return rng.randi_range(min_value, max_value) if rng != null else randi_range(min_value, max_value)
	
## A value as a float for the commands that take numbers: a number or a bool as
## it is, a String by its leading number (0 when it has none), null (a reference
## that could not be resolved, already reported) as 0.
static func to_float(value: Variant) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT, TYPE_BOOL:
			return float(value)
		TYPE_STRING, TYPE_STRING_NAME:
			return str(value).to_float()
		TYPE_NIL:
			return 0.0
	push_error("sequence_runner: not a number: ", value)
	return 0.0

## The value at `path` (`body.radius`, `target.global_position.x`,
## `piece.props.health`, `hand.0`): its head found by path_root(), then per
## segment an Object's property, a Dictionary's key, a Vector2 / Vector3
## component or an Array's index (read_member()). A path of one segment is the
## head itself (`$target`). Null, with an error, when the head or a segment
## cannot be found (a missing dictionary key is one).
func resolve_property_path(path: String) -> Variant:
	var parts := path.split(".")
	var current: Variant = path_root(parts[0])
	if current == null:
		run_error("cannot resolve $" + path)
		return null
	for i: int in range(1, parts.size()):
		var step := read_member(current, parts[i])
		if not step[0]:
			run_error("$%s: %s has no \"%s\"" % [path, type_string(typeof(current)), parts[i]])
			return null
		current = step[1]
	return current

## Where a property path starts: `target` and `self`, then a variable of that
## name (an Object, a Dictionary, a Vector2... whatever it holds; a `$` prefix
## is accepted), then the node at /root/<head> (resolve_target()). Null when
## none is found.
func path_root(head: String) -> Variant:
	var key := head.trim_prefix("$")
	if key != "target" and key != "self" and scratch_pad.has(key) and typeof(scratch_pad[key]) != TYPE_OBJECT:
		return scratch_pad[key]
	return resolve_target(key)

## Reads the member `key` of `container`: an Object's property, a Dictionary's
## key (a String key, or its StringName), a Vector2's or Vector3's component, an
## Array's or packed array's element by index (`0`, `1`... within its size).
## [true, the value], or [false, null] when the container has no such member.
static func read_member(container: Variant, key: String) -> Array:
	var at := _path_index(container, key)
	if at >= 0:
		return [true, container[at]]
	match typeof(container):
		TYPE_OBJECT:
			if is_instance_valid(container) and key in container:
				return [true, (container as Object).get(key)]
		TYPE_DICTIONARY:
			var dict: Dictionary = container
			if dict.has(key):
				return [true, dict[key]]
			if dict.has(StringName(key)):
				return [true, dict[StringName(key)]]
		TYPE_VECTOR2:
			var v2: Vector2 = container
			match key:
				"x":
					return [true, v2.x]
				"y":
					return [true, v2.y]
		TYPE_VECTOR3:
			var v3: Vector3 = container
			match key:
				"x":
					return [true, v3.x]
				"y":
					return [true, v3.y]
				"z":
					return [true, v3.z]
	return [false, null]

# The index a path segment names in an Array or a packed array: `key` all
# digits and within the container's size; -1 otherwise (not an array, not an
# index, out of range).
static func _path_index(container: Variant, key: String) -> int:
	var kind := typeof(container)
	if kind != TYPE_ARRAY and (kind < TYPE_PACKED_BYTE_ARRAY or kind > TYPE_PACKED_VECTOR4_ARRAY):
		return -1
	if key == "" or key.lstrip("0123456789") != "":
		return -1
	var at := key.to_int()
	return at if at >= 0 and at < container.size() else -1

## Writes `value` at the path `prop` (`gravity_scale`, `props.health`,
## `position.x`, `tags.0`) from `root` (an Object, a Dictionary or an Array).
## Every segment but the last is read (read_member()). The last is an Object's
## property, a Dictionary's key (created when missing), a Vector2 / Vector3
## component or an Array's index within its size. A value read on the way (a
## vector) is written back into its parent. False, with an error, when a
## segment cannot be read or written.
func write_property_path(root: Variant, prop: String, value: Variant) -> bool:
	var written := write_path(root, prop.split("."), 0, value)
	if not written[0]:
		run_error("cannot write \"%s\" on %s" % [prop, type_string(typeof(root))])
	return written[0]

## write_property_path()'s step: writes `value` at parts[at...] of `container`;
## [true, the container as written] or [false, container].
static func write_path(container: Variant, parts: PackedStringArray, at: int, value: Variant) -> Array:
	var key := parts[at]
	if at == parts.size() - 1:
		return write_member(container, key, value)
	var step := read_member(container, key)
	if not step[0]:
		return [false, container]
	var child: Variant = step[1]
	var written := write_path(child, parts, at + 1, value)
	if not written[0]:
		return written
	match typeof(child):
		TYPE_OBJECT, TYPE_DICTIONARY, TYPE_ARRAY:
			return [true, container]
	return write_member(container, key, written[1])

## Writes the member `key` of `container` (as read_member() reads it; a
## Dictionary's missing key is created, an Array's element is written only
## within its size; a packed array is not written). [true, the container as
## written] or [false, container] when it has no such member.
static func write_member(container: Variant, key: String, value: Variant) -> Array:
	if typeof(container) == TYPE_ARRAY:
		var at := _path_index(container, key)
		if at < 0:
			return [false, container]
		var list: Array = container
		list[at] = value
		return [true, list]
	match typeof(container):
		TYPE_OBJECT:
			if is_instance_valid(container) and key in container:
				(container as Object).set(key, value)
				return [true, container]
		TYPE_DICTIONARY:
			var dict: Dictionary = container
			if not dict.has(key) and dict.has(StringName(key)):
				dict[StringName(key)] = value
			else:
				dict[key] = value
			return [true, dict]
		TYPE_VECTOR2:
			var v2: Vector2 = container
			match key:
				"x":
					v2.x = to_float(value)
					return [true, v2]
				"y":
					v2.y = to_float(value)
					return [true, v2]
		TYPE_VECTOR3:
			var v3: Vector3 = container
			match key:
				"x":
					v3.x = to_float(value)
					return [true, v3]
				"y":
					v3.y = to_float(value)
					return [true, v3]
				"z":
					v3.z = to_float(value)
					return [true, v3]
	return [false, container]
	
# Factories

func factory_move(args: Dictionary, _index: int) -> Callable:
	var x := str(args.get("x", "0"))
	var y := str(args.get("y", "0"))
	return cmd_move(x, y)
	
func factory_wait(args: Dictionary, _index: int) -> Callable:
	var seconds := str(args.get("seconds", "0"))
	return cmd_wait(seconds)

func factory_goto(args: Dictionary, _index: int) -> Callable:
	var label: String = args.get("label", "")
	return cmd_goto(label)

func factory_play_anim(args: Dictionary, _index: int) -> Callable:
	var anim: String = args.get("anim", "")
	var node_path: String = args.get("node_path", "")
	return cmd_play_anim(anim, node_path)
	
func factory_call(args: Dictionary, _index: int) -> Callable:
	var method: String = args.get("method", "")
	var on: String = args.get("on", "target")
	var call_args: Array = []
	
	var args_index: int = 0
	while args.has("arg%d" % args_index):
		call_args.append(args["arg%d" % args_index])
		args_index += 1
	var var_name: String = args.get("var", "")
	var awaited: bool = str(args.get("await", "false")).to_lower() == "true"
	return cmd_call(on, method, call_args, var_name, awaited)
	
func factory_pause(args: Dictionary, _index: int) -> Callable:
	var time := str(args.get("time", ""))
	return cmd_pause(time)
	
func factory_unpause(_args: Dictionary, _index: int) -> Callable:
	return cmd_unpause()

func factory_set(args: Dictionary, _index: int) -> Callable:
	var var_name: String = args.get("var", "")
	var value: Variant = args.get("value", "0")
	var expr: String = args.get("expr", "")
	return cmd_set(var_name, value, expr)
	
func factory_goto_if(args: Dictionary, _index: int) -> Callable:
	var label: String = args.get("label", "")
	var var_name: String = args.get("var", "")
	var op: String = args.get("op", "0")
	var value: String = args.get("value", "0")
	return cmd_goto_if(label, var_name, op, value)

func factory_wait_signal(args: Dictionary, _index: int) -> Callable:
	var on: String = args.get("on", "target")
	var signal_name: String = args.get("signal", "")
	return cmd_wait_signal(on, signal_name)

func factory_set_prop(args: Dictionary, _index: int) -> Callable:
	return cmd_set_prop(str(args.get("on", "target")), str(args.get("prop", "")), str(args.get("value", "")), str(args.get("expr", "")))

func factory_tween_move(args: Dictionary, _index: int) -> Callable:
	return cmd_tween_move(str(args.get("x", 0)), str(args.get("y", 0)), str(args.get("duration", 0)))

# Blocks: <if> / <else/> and <for_each>, with the end markers the reader adds.

# The block commands the reader closes with an end marker: command -> end marker.
const _BLOCK_ENDS: Dictionary = {"if": "end_if", "for_each": "end_for_each"}

# The for_each loops under way: the <for_each> command's index -> {"items" (the
# copy), "at" (the round), "end" (its end marker's index), "var", "index"}.
# Cleared by start(); a goto out of a loop drops it (jump()).
var _for_each_states: Dictionary = {}
# While a section compiles: what _pair_blocks() found, command index -> its
# partners, for the block factories.
var _block_links: Dictionary = {}

# Pairs a section's blocks with a stack: an <if> (the built-in one) with its
# <else/> and end marker, a <for_each> with its end marker. {"links": index ->
# {"else", "end"} for an opener, {"opener"} for an <else/>, {"opener", "kind"}
# for an end marker; "problems": index -> the compile errors found at that
# command}. A block name a subclass registered itself is not paired: its end
# markers do nothing.
func _pair_blocks(parsed: Array[Dictionary]) -> Dictionary:
	var links: Dictionary = {}
	var problems: Dictionary = {}
	var built_in: Dictionary = {
		"if": command_factories.get("if", Callable()) == factory_if_block,
		"for_each": command_factories.get("for_each", Callable()) == factory_for_each_block,
	}
	var else_built_in: bool = command_factories.get("else", Callable()) == factory_else_block
	var open: Array[int] = []
	for at: int in range(parsed.size()):
		var cmd_name: String = parsed[at].get("name", "")
		var top: int = open.back() if not open.is_empty() else -1
		var top_name: String = parsed[top].get("name", "") if top >= 0 else ""
		if built_in.get(cmd_name, false):
			links[at] = {"else": -1, "end": -1}
			open.append(at)
		elif cmd_name == "else" and else_built_in:
			if top_name != "if":
				_block_problem(problems, at, "<else/> outside an <if>")
			elif links[top]["else"] >= 0:
				_block_problem(problems, at, "a second <else/> in one <if>")
			else:
				links[top]["else"] = at
				links[at] = {"opener": top}
		elif _BLOCK_ENDS.values().has(cmd_name) and not command_factories.has(cmd_name):
			var opener_name: String = _BLOCK_ENDS.find_key(cmd_name)
			if not built_in[opener_name]:
				continue
			if top_name == opener_name:
				open.pop_back()
				links[top]["end"] = at
				links[at] = {"opener": top, "kind": opener_name}
			else:
				_block_problem(problems, at, "</%s> without an <%s>" % [opener_name, opener_name])
	for at: int in open:
		_block_problem(problems, at, "<%s> is not closed" % parsed[at].get("name", ""))
	return {"links": links, "problems": problems}

static func _block_problem(problems: Dictionary, at: int, message: String) -> void:
	if not problems.has(at):
		problems[at] = PackedStringArray()
	var list: PackedStringArray = problems[at]
	list.append(message)
	problems[at] = list

# An end marker's command: a built-in <for_each>'s loops back, any other does
# nothing.
func _compile_block_end(at: int) -> Callable:
	var link: Dictionary = _block_links.get(at, {})
	if link.get("kind", "") == "for_each":
		return _cmd_end_for_each(link["opener"])
	return func() -> Variant: return null

# A goto landed on `to`: the loops whose body does not hold it are abandoned.
func _leave_for_each_loops(to: int) -> void:
	for at: int in _for_each_states.keys():
		if to <= at or to > _for_each_states[at]["end"]:
			_for_each_states.erase(at)

# <if>: when `compiled` (null or broken: false) does not hold, goes on at
# `skip_to` (after its <else/>, or after its end marker).
func _cmd_if_block(compiled: CompiledExpr, skip_to: int) -> Callable:
	return func() -> Variant:
		var holds: bool = false
		if compiled != null and compiled.ok:
			var value: Variant = run_expr(compiled)
			holds = true if value else false
		if not holds:
			index = skip_to
		return null

# <for_each>: copies what `source` resolves to and starts the first round,
# or skips past `end` (an empty array; not an array: an error).
func _cmd_for_each_block(var_name: String, source: String, index_name: String, at: int, end: int) -> Callable:
	return func() -> Variant:
		_for_each_states.erase(at)
		var value: Variant = resolve_value(source)
		var kind := typeof(value)
		var items: Array = []
		if kind == TYPE_ARRAY:
			items = (value as Array).duplicate()
		elif kind >= TYPE_PACKED_BYTE_ARRAY and kind <= TYPE_PACKED_VECTOR4_ARRAY:
			for item: Variant in value:
				items.append(item)
		else:
			run_error("for_each: \"%s\" is %s, not an array" % [source, type_string(kind)])
			index = end + 1
			return null
		if items.is_empty():
			index = end + 1
			return null
		var state: Dictionary = {"items": items, "at": 0, "end": end, "var": var_name, "index": index_name}
		_for_each_states[at] = state
		_for_each_round(state)
		return null

# A for_each's end marker: the next round from the top of the body, or on past
# the loop after the last (or when the loop was abandoned or never entered).
func _cmd_end_for_each(opener: int) -> Callable:
	return func() -> Variant:
		if not _for_each_states.has(opener):
			return null
		var state: Dictionary = _for_each_states[opener]
		state["at"] += 1
		if state["at"] >= (state["items"] as Array).size():
			_for_each_states.erase(opener)
			return null
		_for_each_round(state)
		index = opener + 1
		return null

# Sets a for_each round's variables: its element and (when named) its index.
func _for_each_round(state: Dictionary) -> void:
	var at: int = state["at"]
	if state["var"] != "":
		scratch_pad[state["var"]] = state["items"][at]
	if state["index"] != "":
		scratch_pad[state["index"]] = at

## <if expr="...">: runs the commands up to its <else/> (or its end marker)
## when `expr` (an expression, as set's) holds, else those after its <else/>.
## A missing or malformed expr is a compile error and reads as false.
func factory_if_block(args: Dictionary, at: int) -> Callable:
	var expr := str(args.get("expr", ""))
	if expr == "":
		compile_error("<if> needs expr")
	var compiled := compile_command_expr("if", expr)
	var link: Dictionary = _block_links.get(at, {})
	var end: int = link.get("end", -1)
	if end < 0:
		return func() -> Variant: return null
	var else_at: int = link.get("else", -1)
	return _cmd_if_block(compiled, (else_at if else_at >= 0 else end) + 1)

## <else/>: reached at the end of its <if>'s first part, goes on after the
## <if>'s end marker. Outside an <if> it is a compile error and does nothing.
func factory_else_block(_args: Dictionary, at: int) -> Callable:
	var link: Dictionary = _block_links.get(at, {})
	var opener: Dictionary = _block_links.get(link.get("opener", -1), {})
	var end: int = opener.get("end", -1)
	if end < 0:
		return func() -> Variant: return null
	return func() -> Variant:
		index = end + 1
		return null

## <for_each var="m" in="$list" index="i">: runs its body once per element of
## a copy of the Array (or packed array) `in` resolves to, with `$m` the
## element and `$i` (when named) its index from 0. An empty array skips the
## body; something that is not an array is an error and skips it too.
func factory_for_each_block(args: Dictionary, at: int) -> Callable:
	var source := str(args.get("in", ""))
	if source == "":
		compile_error("<for_each> needs in")
	var link: Dictionary = _block_links.get(at, {})
	var end: int = link.get("end", -1)
	if end < 0:
		return func() -> Variant: return null
	return _cmd_for_each_block(str(args.get("var", "")), source, str(args.get("index", "")), at, end)

## `<stop/>`: ends the sequence with stop() (`stopped` true, `failed` false).
func factory_stop(_args: Dictionary, _index: int) -> Callable:
	return func() -> Variant:
		stop()
		return null

## `<call_return var="..." method="..." ...>`: `<call>` with its `var`
## required, for sequences written for runners that have the two apart. Without
## `var` it is a compile error (and calls all the same).
func factory_call_return(args: Dictionary, at: int) -> Callable:
	if str(args.get("var", "")) == "":
		compile_error("<call_return> needs var")
	return factory_call(args, at)

## `<end/>`: finishes the sequence here, as if it had run to its last command
## (`stopped` and `failed` stay false; `<stop/>` is the one that stops it).
func factory_end(_args: Dictionary, _index: int) -> Callable:
	return func() -> Variant:
		index = sequence.size()
		return null

# Text: <say> and <log>, and the {expression} placeholders of their text.

# The regex of a text's placeholders, made on first use.
static var _placeholder_regex: RegEx = null

## Compiles a command's text (`<say>`'s, `<log>`'s) with its section: an
## Array of its parts in order, a String for the text as written and a
## CompiledExpr for each `{expression}` placeholder (an expression as set's).
## A placeholder that does not parse is a compile_error() naming the command
## `cmd_name` and its attribute `attribute`. run_text() makes the text.
func compile_text(cmd_name: String, attribute: String, text: String) -> Array:
	if _placeholder_regex == null:
		_placeholder_regex = RegEx.new()
		_placeholder_regex.compile("\\{([^{}]+)\\}")
	var parts: Array = []
	var last: int = 0
	for found: RegExMatch in _placeholder_regex.search_all(text):
		if found.get_start() > last:
			parts.append(text.substr(last, found.get_start() - last))
		var compiled := compile_expr(found.get_string(1))
		if not compiled.ok:
			compile_error("<%s> %s \"%s\": %s: %s" % [cmd_name, attribute, text, found.get_string(), compiled.error])
		parts.append(compiled)
		last = found.get_end()
	if last < text.length():
		parts.append(text.substr(last))
	return parts

## The text of compile_text()'s parts: each placeholder's expression run
## (run_expr(), its errors as any expression's) and shown by display_text().
func run_text(parts: Array) -> String:
	var text := ""
	for part: Variant in parts:
		if part is CompiledExpr:
			var compiled: CompiledExpr = part
			if compiled.ok:
				text += display_text(run_expr(compiled))
		else:
			text += str(part)
	return text

## A value as a text shows it: a float without a fraction as an integer (an
## expression counts in floats, so `{$apples + 1}` reads "4", not "4.0"),
## anything else as str() gives it.
static func display_text(value: Variant) -> String:
	if value is float and is_finite(value) and value == floorf(value) and absf(value) < 1e15:
		return str(int(value))
	return str(value)

## `<say text="..." speaker="...">`: shows a line of dialogue through the
## presenter's `say(speaker, text)`, `{expression}` placeholders filled in.
## When say() returns a Signal or is a coroutine, the sequence waits for it
## (the player pressing on); otherwise it goes on at once. Without a presenter
## that has say(), the line is printed.
func factory_say(args: Dictionary, _index: int) -> Callable:
	var speaker_parts := compile_text("say", "speaker", str(args.get("speaker", "")))
	var text_parts := compile_text("say", "text", str(args.get("text", "")))
	return func() -> Variant:
		var speaker := run_text(speaker_parts)
		var text := run_text(text_parts)
		if failed:
			return null
		if presenter == null or not presenter.has_method("say"):
			print("[sequence] %s%s" % [speaker + ": " if speaker != "" else "", text])
			return null
		var result: Variant = presenter.callv("say", [speaker, text])
		if result is Signal:
			return result
		if is_coroutine(result):
			return Signal(result as Object, "completed")
		return null

## `<log text="...">`: hands a line to the presenter's `log(text)`,
## `{expression}` placeholders filled in. Without a presenter that has log(),
## the line is printed.
func factory_log(args: Dictionary, _index: int) -> Callable:
	var text_parts := compile_text("log", "text", str(args.get("text", "")))
	return func() -> Variant:
		var text := run_text(text_parts)
		if failed:
			return null
		if presenter != null and presenter.has_method("log"):
			presenter.callv("log", [text])
		else:
			print("[sequence] %s" % text)
		return null

# Subroutines: <gosub> and <return/>.

## How deep `<gosub>` may nest (a subroutine that calls itself...). A `<gosub>`
## that would go deeper is a run-time error and does not jump.
const MAX_GOSUB_DEPTH: int = 64

# The gosubs under way, the innermost last: {"index": the command its
# <return/> goes on at, "loops": the for_each loops of the code that called
# it}. Cleared by start().
var _gosub_stack: Array[Dictionary] = []

## `<gosub label="...">`: jumps to the label and remembers the command after
## itself, where the next `<return/>` goes on. The for_each loops under way
## are set aside until then, so the subroutine may sit outside them and jump
## about without ending them. A label the section lacks is a compile error.
func factory_gosub(args: Dictionary, _index: int) -> Callable:
	var label := str(args.get("label", ""))
	return func() -> Variant:
		if not labels.has(label):
			run_error("gosub: no label \"%s\" in the section" % label)
			return null
		if _gosub_stack.size() >= MAX_GOSUB_DEPTH:
			run_error("gosub: more than %d nested gosubs (MAX_GOSUB_DEPTH); \"%s\" is not run" % [MAX_GOSUB_DEPTH, label])
			return null
		if verbose:
			print("Gosub: ", label)
		_gosub_stack.append({"index": index, "loops": _for_each_states})
		_for_each_states = {}
		index = labels[label]
		return null

## `<return/>`: goes on after the last `<gosub>` still open, with the for_each
## loops it set aside. With no gosub open it is a run-time error and does
## nothing.
func factory_return(_args: Dictionary, _index: int) -> Callable:
	return func() -> Variant:
		if _gosub_stack.is_empty():
			run_error("return: no gosub to return from")
			return null
		var frame: Dictionary = _gosub_stack.pop_back()
		index = frame["index"]
		_for_each_states = frame["loops"]
		return null

# Options: <choose> and its <option> children.

## The commands whose `<option>` children the reader lists in their arguments
## instead of reading them as commands.
const OPTION_PARENTS: PackedStringArray = ["choose"]
## The key of that list in the command's arguments: an Array of Dictionaries,
## one per `<option>`, its attributes. No XML attribute can have this name.
const OPTIONS_ARG: String = "<option>"

## `<choose>` with `<option goto="..." weight="..."/>` children: jumps to one
## option's label at random, on the runner's rng. An option's chance is its
## `weight` (a token, default 1; 0 or less: never) over the sum of them all.
## No option, or an option to a label the section lacks, is a compile error.
## No weight above 0 is a run-time error and nothing jumps.
func factory_choose(args: Dictionary, _index: int) -> Callable:
	var options: Array = args.get(OPTIONS_ARG, [])
	if options.is_empty():
		compile_error("<choose> needs at least one <option>")
	for option: Dictionary in options:
		check_attributes("option", option, PackedStringArray(["goto", "weight"]))
	return func() -> Variant:
		var weights: Array[float] = []
		var total: float = 0.0
		for option: Dictionary in options:
			var weight := maxf(to_float(resolve_value(str(option.get("weight", "1")))), 0.0)
			weights.append(weight)
			total += weight
		if failed:
			return null
		if total <= 0.0:
			run_error("choose: no option has a weight above 0")
			return null
		var roll := random(0.0, total)
		var picked: int = -1
		var passed: float = 0.0
		for i: int in range(options.size()):
			if weights[i] <= 0.0:
				continue
			picked = i
			passed += weights[i]
			if roll < passed:
				break
		jump(str(options[picked].get("goto", "")))
		return null

# Sub-sequences: <run>.

# How deep this runner is in a chain of <run>s (0: started by the game).
var _run_depth: int = 0
# The <run> children running now: stop() stops them.
var _run_children: Array[sequence_runner] = []

## <run section="..." file="..." var="...">: runs the section `section` ("":
## the unnamed one) of `file` (default: this runner's file) on a child runner
## and waits until it ends (see _cmd_run_section()). When neither `file` nor
## `section` is a `$` reference and the file can be read, a section it lacks
## is a compile error; otherwise it is found out at run time.
func factory_run_section(args: Dictionary, _index: int) -> Callable:
	var file := str(args.get("file", ""))
	var section := str(args.get("section", ""))
	var var_name := str(args.get("var", ""))
	if not file.begins_with("$") and not section.begins_with("$"):
		var path := file if file != "" else _compile_path
		if path != "" and FileAccess.file_exists(path) and not read_sections(path, _quiet).has(section):
			compile_error("<run>: %s has no section \"%s\"" % [path, section])
	return _cmd_run_section(file, section, var_name)

# <run>: resolves the file and section, then runs the section on a child
# runner: an instance of this runner's own script, added as its child, with
# its target, rng, verbose, stop_on_error and max_instant_steps, one level
# deeper, and a shallow copy of the scratch pad without `result`. The file's
# <trigger> is ignored. Instant when the child ends inside its start, async
# otherwise (the loop waits for it). A section the file lacks, or a <run>
# nested deeper than MAX_RUN_DEPTH, is a run-time error and nothing runs.
func _cmd_run_section(file_token: String, section_token: String, var_name: String) -> Callable:
	return func() -> Variant:
		var path: Variant = xml_path if file_token == "" else resolve_value(file_token)
		var section: Variant = resolve_value(section_token)
		if failed:
			return null
		if path == null or section == null:
			run_error("run: cannot resolve the file and/or the section: \"%s\" \"%s\"" % [file_token, section_token])
			return null
		var run_path := str(path)
		var run_section := str(section)
		if _run_depth >= MAX_RUN_DEPTH:
			run_error("run: more than %d nested sub-sequences (MAX_RUN_DEPTH); %s:%s is not run" % [MAX_RUN_DEPTH, run_path, run_section])
			return null
		if not read_sections(run_path).has(run_section):
			run_error("run: %s has no section \"%s\"" % [run_path, run_section])
			return null
		var child := (get_script() as Script).new() as sequence_runner
		child.target = target
		child.rng = rng
		child.presenter = presenter
		child.verbose = verbose
		child.stop_on_error = stop_on_error
		child.max_instant_steps = max_instant_steps
		child._run_depth = _run_depth + 1
		add_child(child)
		var vars: Dictionary = scratch_pad.duplicate()
		vars.erase("result")
		if verbose:
			print("Running: %s:%s" % [run_path, run_section])
		_run_children.append(child)
		var run_id := _run_id
		if not child._start_section(run_path, vars, run_section, false):
			_run_children.erase(child)
			child.free()
			return null
		if not child.running:
			_end_run_child(child, var_name, run_id, true)
			return null
		# callv() hands back the coroutine's state (as call's methods do).
		var state: Object = callv("_await_run_child", [child, var_name, run_id])
		return Signal(state, "completed")

# Waits for an async <run> child to end, then _end_run_child().
func _await_run_child(child: sequence_runner, var_name: String, run_id: int) -> void:
	await child.sequence_finished
	_end_run_child(child, var_name, run_id, false)

# A <run> child ended: it is freed (at once when it ended inside its start,
# else once its sequence_finished is over). If this runner is still in the
# same run, a failed child fails it when stop_on_error is on (run_error());
# otherwise `var_name` gets the child's $result (null when it set none).
func _end_run_child(child: sequence_runner, var_name: String, run_id: int, instant: bool) -> void:
	_run_children.erase(child)
	var result: Variant = child.scratch_pad.get("result")
	var child_failed: bool = child.failed
	var where := "%s:%s" % [child.xml_path, child.current_section]
	if instant:
		child.free()
	else:
		child.queue_free()
	if run_id != _run_id or not running:
		return
	if child_failed and stop_on_error:
		run_error("run: the sub-sequence %s failed" % where)
		return
	if var_name != "":
		scratch_pad[var_name] = result
