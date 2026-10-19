class_name sequence_runner
extends Node
## Parsed files: path -> {section name -> its commands}, the unnamed section under "".
static var xml_cache: Dictionary = {}
static var trigger_cache: Dictionary = {}
## Label maps: path -> {section name -> {label -> command index}}.
static var label_cache: Dictionary = {}
## What reading a file found wrong (a duplicate section...): path -> its problems.
static var problem_cache: Dictionary = {}

#Reusable sequence runner. Attach to node, set xml_path, then call start()

## The XML sequence file start() runs when it is given no path.
@export_file("*.xml") var xml_path: String = ""
## Start the sequence on _ready.
@export var auto_start: bool = false
## Drive the runner node itself instead of its parent.
@export var target_self: bool = false
## Print what the runner does (its target, each goto's jump) for debugging.
@export var verbose: bool = false

var target: Node = null
var sequence: Array[Callable] = []
## The section of xml_path the runner plays ("": the unnamed one).
var current_section: String = ""
## The playing section's labels: name -> command index.
var labels: Dictionary = {}
var running: bool = false
var index: int = 0
var scratch_pad: Dictionary = {}
var command_factories: Dictionary = {}
var trigger_config: Dictionary = {}

signal sequence_finished


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	#var parsed = parse_xml("res://data/sequences/test.xml")
	#sequence = compile_sequence(parsed)
	#run_sequence(sequence)
	#pass # Replace with function body.
	
## Runs the section `section` ("": the unnamed <sequence>) of the file at `path`
## (or xml_path). `vars` seeds the scratch pad after its reset, so the sequence
## can read them as `$name`. Returns false, with an error, when the file has no
## such section (or cannot be read): nothing runs and sequence_finished is not
## emitted.
func start(path: String = "", vars: Dictionary = {}, section: String = "") -> bool:
	xml_path = path if path != "" else xml_path
	if xml_path == "":
		printerr("sequence_runner: no xml path set")
		return false
	var parsed := parse_xml(xml_path)
	if not parsed.has(section):
		if not parsed.is_empty():
			printerr("sequence_runner: %s has no section \"%s\"" % [xml_path, section])
		return false
	index = 0
	current_section = section
	scratch_pad = {}
	scratch_pad.merge(vars)
	var commands: Array[Dictionary] = parsed[section]
	labels = label_map(commands)
	if not label_cache.has(xml_path):
		label_cache[xml_path] = {}
	label_cache[xml_path][section] = labels
	sequence = compile_sequence(commands)
	scratch_pad.merge(labels, true)
	if trigger_config.size() > 0:
		setup_trigger()
	else:
		run_sequence(sequence)
	return true
		
#sequence_runner.attach($node, "res://data/sequences/whatever.xml")
## `vars` seed the scratch pad and `section` picks the section when `auto` starts
## the runner here.
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
	
func register_commands() -> void:
	command_factories = {
		"move": factory_move,
		"wait": factory_wait,
		#"label": factory_label,
		"goto": factory_goto,
		"play_anim": factory_play_anim,
		"call": factory_call,
		"pause": factory_pause,
		"unpause": factory_unpause,
		"set": factory_set,
		"goto_if": factory_goto_if,
		"tween_move": factory_tween_move,
		"wait_signal": factory_wait_signal,
		"set_prop": factory_set_prop
	}


#func make_sequence() -> Array[Callable]:
	#var new_sequence: Array[Callable] = []
	#new_sequence.append(cmd_label("start", new_sequence.size()))
	#new_sequence.append(cmd_wait(0.25))
	#new_sequence.append(cmd_move(Vector2(64,64)))
	#new_sequence.append(cmd_wait(0.25))
	#new_sequence.append(cmd_move(Vector2(100,100)))
	#new_sequence.append(cmd_goto("start")) 
	#
	#return new_sequence
	
## A section's labels: label name -> the index of its (no-op) command.
static func label_map(parsed: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for i: int in range(parsed.size()):
		var cmd: Dictionary = parsed[i]
		if cmd.get("name", "") == "label":
			result[cmd["args"].get("name", "")] = i
	return result

func compile_sequence(parsed: Array[Dictionary]) -> Array[Callable]:
	var result : Array[Callable] = []

	for cmd: Dictionary in parsed:
		var cmd_name: String = cmd.get("name", "")
		if cmd_name == "label":
			result.append(func() -> Variant: return null)
			continue
		var args: Dictionary = cmd.get("args", {})
		if command_factories.has(cmd_name):
			result.append(command_factories[cmd_name].call(args, result.size()))
		else:
			printerr("Unknown command: ", cmd_name)
			result.append(func() -> Variant: return null)
	return result
		
	
func cmd_move(x_token: String, y_token: String) -> Callable:
	return func() -> Variant:
		if target:
			var x := to_float(resolve_value(x_token))
			var y := to_float(resolve_value(y_token))
			target.global_position = Vector2(x, y)
			#target.global_position = position
		return null
	
func cmd_wait(time_token: String = "0") -> Callable:
	return func() -> Variant:
		var time := to_float(resolve_value(time_token))
		#print("waiting...")
		return get_tree().create_timer(time).timeout
		
func cmd_pause(time_token: String = "0.016") -> Callable:
	return func() -> Variant:
		#print("waiting...")
		get_tree().paused = true
		var time := to_float(resolve_value(time_token))
		if time > 0:
			var timer := get_tree().create_timer(time, true, false, false)
			timer.timeout.connect(func() -> void: get_tree().paused = false)
			return timer.timeout
		printerr("cmd_pause: Pause time is zero. Exclude time param or set to > 0")
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

## Moves the playing section to its label `label` (an error when it has none).
func jump(label: String) -> void:
	if labels.has(label):
		index = labels[label]
	else:
		printerr("sequence_runner: no label \"%s\" in section \"%s\" of %s" % [label, current_section, xml_path])
		
#func cmd_label(label: String, index: int) -> Callable:
	#scratch_pad[label] = index
	#return func():
		#return null
		
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
			printerr("cmd_play_anim: No Animatable nodes found")
		#anim_target.play(anim)
		
		#print("Playing anim: ", anim)
		return null
		
func find_animated_sprite(node: Node) -> AnimatedSprite2D:
	for child: Node in node.get_children():
		if child is AnimatedSprite2D:
			return child as AnimatedSprite2D
		var result := find_animated_sprite(child)
		if result:
			return result
	return null
		
func cmd_call(on: String, method: String, args_tokens: Array) -> Callable:
	return func() -> Variant:
		var target_node: Object = resolve_target(on)
		var resolved_args: Array = []
		for token: Variant in args_tokens:
			if token is String:
				resolved_args.append(to_number(resolve_value(token)))
			else:
				resolved_args.append(token)
		if target_node and target_node.has_method(method):
			target_node.callv(method, resolved_args)
		else:
			printerr("cmd_call: cannot locate object and/or method: ", on, ":", method)
		return null
		
## Waits for `signal_name` on the object `on` names (resolved like call's `on`).
func cmd_wait_signal(on: String, signal_name: String) -> Callable:
	return func() -> Variant:
		var source: Object = resolve_target(on)
		if source and source.has_signal(signal_name):
			return Signal(source, signal_name)
		printerr("cmd_wait_signal: cannot locate object and/or signal: ", on, ":", signal_name)
		return null
		
func cmd_set(var_name: String, value: Variant, expr: String) -> Callable:
	return func() -> Variant:
		if expr != "":
			scratch_pad[var_name] = evaluate_expr(expr)
		else:
			scratch_pad[var_name] = resolve_value(value) if value is String else value
		return null
			
## Writes at the path `prop` of what `on` names (an object as call's `on`
## resolves it, or a scratch-pad dictionary; path_root()): `value` resolved as a
## token, or `expr` evaluated as set's.
func cmd_set_prop(on: String, prop: String, value_token: String, expr: String) -> Callable:
	return func() -> Variant:
		var root: Variant = path_root(on)
		if root == null:
			printerr("sequence_runner: set_prop: cannot locate object: ", on)
			return null
		var value: Variant = evaluate_expr(expr) if expr != "" else to_number(resolve_value(value_token))
		write_property_path(root, prop, value)
		return null

func cmd_goto_if(label: String, var_token: String, op: String, value_token: String) -> Callable:
	return func() -> Variant:
		var a: float = NAN
		if scratch_pad.has(var_token):
			a = to_float(scratch_pad.get(var_token, 0))
		else:
			a = to_float(resolve_value(var_token))
		if is_nan(a):
			printerr("cmd_goto_if: Cannot resolve first operand: ", var_token)
			return null
		var b: float = NAN
		if scratch_pad.has(value_token):
			b = to_float(scratch_pad.get(value_token))
		else:
			b = to_float(resolve_value(value_token))
		if is_nan(b):
			printerr("cmd_goto_if: Cannot resolve second operand: ", value_token)
			return null
		#var b := float(value)
		var result := false
		match op:
			"eq":
				result = a == b
			"!=":
				result = a != b
			"<":
				result = a < b
			">":
				result = a > b
			"<=":
				result = a <= b
			">=":
				result = a >= b
			"mod":
				result = !fmod(a, b)
			_:
				printerr("cmd_goto_if: unknown operator: ", op)
		if result:
			jump(label)
		return null
	
func cmd_tween_move(x_token: String, y_token: String, dur_token: String) -> Callable:
	return func() -> Variant:
		var pos := Vector2(to_float(resolve_value(x_token)), to_float(resolve_value(y_token)))
		var tween := create_tween()
		tween.tween_property(target, "global_position", pos, to_float(resolve_value(dur_token)))
		return tween.finished
		
func run_sequence(commands: Array[Callable]) -> void:
	if running:
		return
	running = true
	sequence = commands
	
	while running && index < sequence.size():
		var current: Callable = sequence[index]
		index = index + 1
		#print("running command: ", index, " : ", current)
		
		if current.is_valid():
			var result: Variant = current.call()
			if result is Signal:
				await result
		else:
			printerr("Invalid sequence command: ", index - 1)
	
	running = false
	sequence_finished.emit()
	
## The sections of the file at `path` (read_sections()) and its <trigger> as
## trigger_config.
func parse_xml(path: String) -> Dictionary:
	var parsed := read_sections(path)
	trigger_config = trigger_cache.get(path, {})
	return parsed

## Reads the file at `path` once (cached): section name -> its commands
## ({"name": element, "args": {attribute: value}}), the unnamed <sequence> under
## "", in file order; its <trigger> goes to trigger_cache. A second section of
## the same name is dropped as a problem (problem_cache). Empty for a file that
## cannot be read: an error unless `quiet`.
static func read_sections(path: String, quiet: bool = false) -> Dictionary:
	if xml_cache.has(path):
		return xml_cache[path]
	var parser := XMLParser.new()
	var result: Dictionary = {}
	var valid := parser.open(path)
	if valid != OK:
		if not quiet:
			printerr("sequence_runner: could not open XML file for command parsing: ", path)
		return result
	var problems := PackedStringArray()
	var commands: Array[Dictionary] = []
	var found_sequence := false
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT:
			var node_name := parser.get_node_name()

			if node_name == "trigger":
				var config: Dictionary = {}
				for arg: int in range(parser.get_attribute_count()):
					config[parser.get_attribute_name(arg)] = parser.get_attribute_value(arg)
				trigger_cache[path] = config
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

				commands.append({
					"name": node_name,
					"args": arguments
					})
		elif parser.get_node_type() == XMLParser.NODE_ELEMENT_END:
			if parser.get_node_name() == "sequence":
				found_sequence = false
	xml_cache[path] = result
	problem_cache[path] = problems
	if not quiet:
		for problem: String in problems:
			printerr("sequence_runner: %s: %s" % [path, problem])
	return result
				
				 
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
				printerr("setup_trigger: couln't locate source/signal")
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
		

#func compile_sequence(parsed: Array[Dictionary] -> Array[Callable]:

func evaluate_expr(expr: String) -> Variant:
	var tokens := expr.split(" ")
	
	if tokens.size() == 1:
		return resolve_value(tokens[0])
	if tokens.size() == 3:
		var left := to_float(resolve_value(tokens[0]))
		var operator := str(tokens[1])
		var right := to_float(resolve_value(tokens[2]))
		match operator:
			"+":
				return left + right
			"-":
				return left - right
			"*":
				return left * right
			"/":
				if right != 0:
					return left / right
				else:
					printerr("evaluate_expr: attempt to divide by zero")
					return 0
			_:
				printerr("evaluate_expr: unknown operator: ", operator)
			
	printerr("evaluate_expr: malformed expression: ", expr)
	return 0
			
	
## The object `path` names (call's and wait_signal's `on`, the head of a
## property path): `target`, `self`, then a scratch-pad entry of that name
## holding an Object (a `$` prefix is accepted and stripped; an object handed in
## with start()'s vars), then the node at `/root/<path>`, cached for the run as
## `target_<path>` (scratch-pad objects are not cached). Null when none is found.
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
		printerr("sequence_runner: $%s was freed" % key)
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
	
## A String that reads as an int or a float becomes that number, so a call's
## arguments reach typed parameters; any other value is returned as it is.
func to_number(value: Variant) -> Variant:
	if value is String:
		var text: String = value
		if text.is_valid_int():
			return text.to_int()
		if text.is_valid_float():
			return text.to_float()
	return value
	
func resolve_random(token: String) -> float:
	var opperands := token.trim_prefix("random(").trim_suffix(")")
	var parts := opperands.split(",")
	if parts.size() != 2:
		printerr("resolve_random: Expected 'random(min,max),' got: ", token)
		return 0.0
	var min_val := to_float(resolve_value(parts[0].strip_edges()))
	var max_val := to_float(resolve_value(parts[1].strip_edges()))
	return randf_range(min_val, max_val)
	
func resolve_random_int(token: String) -> int:
	var opperands := token.trim_prefix("random_int(").trim_suffix(")")
	var parts := opperands.split(",")
	if parts.size() != 2:
		printerr("resolve_random_int: Expected 'random_int(min,max),' got: ", token)
		return 0
	var min_val := int(to_float(resolve_value(parts[0].strip_edges())))
	var max_val := int(to_float(resolve_value(parts[1].strip_edges())))
	return randi_range(min_val, max_val)
	
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
	printerr("sequence_runner: not a number: ", value)
	return 0.0

## The value at `path` (`body.radius`, `target.global_position.x`,
## `piece.props.health`): its head found by path_root(), then per segment an
## Object's property, a Dictionary's key or a Vector2 / Vector3 component
## (read_member()). A path of one segment is the head itself (`$target`).
## Null, with an error, when the head or a segment cannot be found (a missing
## dictionary key is one).
func resolve_property_path(path: String) -> Variant:
	var parts := path.split(".")
	var current: Variant = path_root(parts[0])
	if current == null:
		printerr("sequence_runner: unresolvable reference: $", path)
		return null
	for i: int in range(1, parts.size()):
		var step := read_member(current, parts[i])
		if not step[0]:
			printerr("sequence_runner: $%s: %s has no \"%s\"" % [path, type_string(typeof(current)), parts[i]])
			return null
		current = step[1]
	return current

## Where a property path starts: `target` and `self`, then a scratch-pad
## variable of that name (an Object, a Dictionary, a Vector2... whatever it
## holds; a `$` prefix is accepted), then the node at /root/<head>
## (resolve_target()). Null when none is found.
func path_root(head: String) -> Variant:
	var key := head.trim_prefix("$")
	if key != "target" and key != "self" and scratch_pad.has(key) and typeof(scratch_pad[key]) != TYPE_OBJECT:
		return scratch_pad[key]
	return resolve_target(key)

## Reads the member `key` of `container`: an Object's property, a Dictionary's
## key (a String key, or its StringName), a Vector2's or Vector3's component.
## [true, the value], or [false, null] when the container has no such member.
static func read_member(container: Variant, key: String) -> Array:
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

## Writes `value` at the path `prop` (`gravity_scale`, `props.health`,
## `position.x`) from `root` (an Object or a Dictionary). Every segment but the
## last is read (read_member()); the last is an Object's property, a
## Dictionary's key (created when missing) or a Vector2 / Vector3 component, and
## a value read on the way (a vector) is written back into its parent. False,
## with an error, when a segment cannot be read or written.
func write_property_path(root: Variant, prop: String, value: Variant) -> bool:
	var written := write_path(root, prop.split("."), 0, value)
	if not written[0]:
		printerr("sequence_runner: cannot write \"%s\" on %s" % [prop, type_string(typeof(root))])
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
## Dictionary's missing key is created). [true, the container as written] or
## [false, container] when it has no such member.
static func write_member(container: Variant, key: String, value: Variant) -> Array:
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
	
#Factories

func factory_move(args: Dictionary, _index: int) -> Callable:
	var x := str(args.get("x", "0"))
	var y := str(args.get("y", "0"))
	return cmd_move(x, y)
	
func factory_wait(args: Dictionary, _index: int) -> Callable:
	var seconds := str(args.get("seconds", "0"))
	return cmd_wait(seconds)
	
#func factory_label(args: Dictionary, index: int) -> Callable:
	#var label_name: String = args.get("name", "")
	#return cmd_label(label_name, index)
	
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
	return cmd_call(on, method, call_args)
	
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
	var lable: String = args.get("label", "")
	var var_name: String = args.get("var", "")
	var op: String = args.get("op", "0")
	var value: String = args.get("value", "0")
	return cmd_goto_if(lable, var_name, op, value)

func factory_wait_signal(args: Dictionary, _index: int) -> Callable:
	var on: String = args.get("on", "target")
	var signal_name: String = args.get("signal", "")
	return cmd_wait_signal(on, signal_name)

func factory_set_prop(args: Dictionary, _index: int) -> Callable:
	return cmd_set_prop(str(args.get("on", "target")), str(args.get("prop", "")), str(args.get("value", "")), str(args.get("expr", "")))

func factory_tween_move(args: Dictionary, _index: int) -> Callable:
	return cmd_tween_move(str(args.get("x", 0)), str(args.get("y", 0)), str(args.get("duration", 0)))
