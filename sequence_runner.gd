class_name sequence_runner
extends Node
static var xml_cache: Dictionary = {}
static var trigger_cache: Dictionary = {}
static var label_cache: Dictionary = {}

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
	
## Runs the sequence at `path` (or xml_path). `vars` seeds the scratch pad after
## its reset, so the sequence can read them as `$name`.
func start(path: String = "", vars: Dictionary = {}) -> void:
	xml_path = path if path != "" else xml_path
	if xml_path == "":
		printerr("sequence_runner: no xml path set")
		return
	index = 0
	scratch_pad = {}
	scratch_pad.merge(vars)
	var parsed := parse_xml(xml_path)
	sequence = compile_sequence(parsed)
	if label_cache.has(xml_path):
		scratch_pad.merge(label_cache[xml_path], true)
	if not sequence:
		printerr("No compiled sequence found")
		return
	if trigger_config.size() > 0:
		setup_trigger()
	else:
		run_sequence(sequence)
		
#sequence_runner.attach($node, "res://data/sequences/whatever.xml")
## `vars` seed the scratch pad when `auto` starts the runner here.
static func attach(node: Node, xml: String, auto: bool = false, vars: Dictionary = {}) -> sequence_runner:
	var runner := sequence_runner.new()
	runner.xml_path = xml
	node.add_child(runner)
	if auto:
		runner.start("", vars)
	return runner
	
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
		"wait_signal": factory_wait_signal
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
	
func compile_sequence(parsed: Array[Dictionary]) -> Array[Callable]:
	var result : Array[Callable] = []
	#store labels first:
	var label_map: Dictionary = {}
	for i: int in range(parsed.size()):
		var cmd: Dictionary = parsed[i]
		if cmd.get("name", "") == "label":
			label_map[cmd["args"].get("name", "")] = i
			
	label_cache[xml_path] = label_map
	
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
			var x := float(resolve_value(x_token))
			var y := float(resolve_value(y_token))
			target.global_position = Vector2(x, y)
			#target.global_position = position
		return null
	
func cmd_wait(time_token: String = "0") -> Callable:
	return func() -> Variant:
		var time := float(resolve_value(time_token))
		#print("waiting...")
		return get_tree().create_timer(time).timeout
		
func cmd_pause(time_token: String = "0.016") -> Callable:
	return func() -> Variant:
		#print("waiting...")
		get_tree().paused = true
		var time := float(resolve_value(time_token))
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
		index = scratch_pad[label]
		return null
		
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
			
func cmd_goto_if(label: String, var_token: String, op: String, value_token: String) -> Callable:
	return func() -> Variant:
		var a: float = NAN
		if scratch_pad.has(var_token):
			a = float(scratch_pad.get(var_token, 0))
		else:
			a = float(resolve_value(var_token))
		if is_nan(a):
			printerr("cmd_goto_if: Cannot resolve first operand: ", var_token)
			return null
		var b: float = NAN
		if scratch_pad.has(value_token):
			b = float(scratch_pad.get(value_token))
		else:
			b = float(resolve_value(value_token))
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
			index = scratch_pad[label]
		return null
	
func cmd_tween_move(x_token: String, y_token: String, dur_token: String) -> Callable:
	return func() -> Variant:
		var pos := Vector2(float(resolve_value(x_token)), float(resolve_value(y_token)))
		var tween := create_tween()
		tween.tween_property(target, "global_position", pos, float(resolve_value(dur_token)))
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
	
func parse_xml(path: String) -> Array[Dictionary]:
	if xml_cache.has(path):
		if trigger_cache.has(path):
			trigger_config = trigger_cache[path]
		return xml_cache[path]
	var parser := XMLParser.new()
	var result: Array[Dictionary] = []
	var valid := parser.open(path)
	if valid != OK:
		printerr("Could not open XML file for command parsing: ", path)
		return result
	var found_sequence := false
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT:
			var node_name := parser.get_node_name()
			
			if node_name == "trigger":
				trigger_config = {}
				for arg: int in range(parser.get_attribute_count()):
					trigger_config[parser.get_attribute_name(arg)] = parser.get_attribute_value(arg)
				trigger_cache[path] = trigger_config
				continue
			
			if node_name == "sequence":
				found_sequence = true
				continue
			if found_sequence:
				var arguments: Dictionary = {}
				for arg: int in range(parser.get_attribute_count()):
					arguments[parser.get_attribute_name(arg)] = parser.get_attribute_value(arg)
				
				result.append({
					"name": node_name,
					"args": arguments
					})
		elif parser.get_node_type() == XMLParser.NODE_ELEMENT_END:
			if parser.get_node_name() == "sequence":
				found_sequence = false
	xml_cache[path] = result
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
		var left := float(resolve_value(tokens[0]))
		var operator := str(tokens[1])
		var right := float(resolve_value(tokens[2]))
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
			
	
func resolve_target(path: String) -> Object:
	if scratch_pad.has("target_" + path):
		return scratch_pad.get("target_" + path)
	var result: Object
	match path:
		"target":
			result = target
			
		"self":
			result = self
		_:
			result = get_node_or_null("/root/" + path)
	scratch_pad["target_" + path] = result
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
	if "." in ref:
		return resolve_property_path(ref)
		
	printerr("resolve_value: unresolvable reference: ", token)
	return float(token)
	
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
	var min_val := float(resolve_value(parts[0].strip_edges()))
	var max_val := float(resolve_value(parts[1].strip_edges()))
	return randf_range(min_val, max_val)
	
func resolve_random_int(token: String) -> int:
	var opperands := token.trim_prefix("random_int(").trim_suffix(")")
	var parts := opperands.split(",")
	if parts.size() != 2:
		printerr("resolve_random_int: Expected 'random_int(min,max),' got: ", token)
		return 0
	var min_val := int(resolve_value(parts[0].strip_edges()))
	var max_val := int(resolve_value(parts[1].strip_edges()))
	return randi_range(min_val, max_val)
	
func resolve_property_path(path: String) -> Variant:
	var parts := path.split(".")
	var obj := resolve_target(parts[0])
	if obj == null:
		printerr("resolve_property: can't locate object: ", parts[0])
		return 0
	var current: Variant = obj
	for i: int in range(1, parts.size()):
		var prop: String = parts[i]
		if current is Object && prop in current:
			current = current.get(prop)
		elif current is Vector2:
			match prop:
				"x":
					current = current.x
				"y":
					current = current.y
				_:
					printerr("resolve_property_path: invalid Vector2 propewrty: ", prop)
					return 0
		elif current is Vector3:
			match prop:
				"x":
					current = current.x
				"y":
					current = current.y
				"z":
					current = current.z
				_:
					printerr("resolve_property_path: invalid Vector3 propewrty: ", prop)
					return 0
		else:
			printerr("resolve_property_path: Cannot access property ", prop, " on: ", current, " of type: ", typeof(current))
			return 0
	return current
	
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

func factory_tween_move(args: Dictionary, _index: int) -> Callable:
	return cmd_tween_move(str(args.get("x", 0)), str(args.get("y", 0)), str(args.get("duration", 0)))
