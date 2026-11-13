extends TestCase
## The regression suite of sequence_runner.gd: what projects using the addon rely
## on. The built-in commands, variables, triggers, then one fixture per feature:
## named sections, named objects, dictionary paths, set_prop, call var= / await=,
## errors and validate(), the seeded rng, typed values, stop(), goto_if on strings
## and its aliases lt / gt / le / ge, and the free-form expressions. Fixtures:
## tests/fixtures/sequences/ (all compile) and tests/fixtures/broken_sequences/
## (compile problems on purpose). A change to the addon may add tests here; an
## existing one changes only when the behaviour it pins is changed on purpose.

const DIR: String = "res://fixtures/sequences/"
## Files with compile problems, for validate() (kept apart: every file in DIR validates).
const BROKEN_DIR: String = "res://fixtures/broken_sequences/"

## The node a runner drives: records the calls its sequences make.
class Recorder extends Node2D:
	signal fired
	signal drop_finished

	var pings: int = 0
	var radius: int = 7
	var props: Dictionary = {}
	var rolls: Array[int] = []
	var damage_taken: Array[int] = []
	var scales: Array[float] = []
	var said: Array[String] = []
	var taken: Array = []

	func ping() -> void:
		pings += 1

	func record(n: int) -> void:
		rolls.append(n)

	func take_damage(n: int) -> void:
		damage_taken.append(n)

	func scale_by(f: float) -> void:
		scales.append(f)

	func say(text: String) -> void:
		said.append(text)

	func double(n: int) -> int:
		return n * 2

	## Keeps its four arguments as they came, types and all.
	func take(a: Variant, b: Variant, c: Variant, d: Variant) -> void:
		taken = [a, b, c, d]

	## A method returning a signal: `fired`.
	func fired_signal() -> Signal:
		return fired

	## A coroutine: returns 5 once drop_finished is emitted.
	func slow_value() -> int:
		await drop_finished
		return 5

var host: Recorder

func before_each() -> void:
	host = Recorder.new()
	add_child(host)

## A runner on the host for the fixture `file`, not started.
func _runner(file: String) -> sequence_runner:
	return sequence_runner.attach(host, DIR + file)

## A one-frame SpriteFrames holding the animation `anim`.
func _frames(anim: StringName) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.add_animation(anim)
	frames.add_frame(anim, PlaceholderTexture2D.new())
	return frames

func test_counted_loop_calls_five_times() -> void:
	var runner := _runner("counted_loop.xml")
	runner.start()
	assert_eq(host.pings, 5)
	assert_false(runner.running)

func test_random_int_yields_integers_in_range() -> void:
	var runner := _runner("random_int.xml")
	for i: int in 20:
		runner.start()
	assert_eq(host.rolls.size(), 40)
	var seen: Dictionary[int, bool] = {}
	for roll: int in host.rolls:
		assert_true(roll >= 1 and roll <= 6, "roll %d outside 1..6" % roll)
		seen[roll] = true
	assert_gt(seen.size(), 2, "40 rolls of a die should show more than two faces")

func test_call_converts_numeric_arguments() -> void:
	var runner := _runner("numeric_arg.xml")
	runner.start()
	assert_eq(host.damage_taken, [6] as Array[int])
	assert_eq(host.scales, [0.5] as Array[float])
	assert_eq(host.said, ["hello"] as Array[String], "a non-numeric argument stays a string")

func test_start_vars_seed_the_scratch_pad() -> void:
	var runner := _runner("seeded_vars.xml")
	runner.start("", {"damage": 12})
	assert_eq(host.damage_taken, [12] as Array[int])

func test_attach_auto_start_passes_vars() -> void:
	sequence_runner.attach(host, DIR + "seeded_vars.xml", true, {"damage": 3})
	assert_eq(host.damage_taken, [3] as Array[int])

func test_wait_and_tween_move_finish() -> void:
	var runner := _runner("wait_and_tween.xml")
	runner.start()
	assert_true(runner.running, "the wait should hold the sequence")
	assert_true(await await_signal(runner.sequence_finished, 2.0), "sequence_finished never fired")
	assert_false(runner.running)
	assert_almost_eq(host.global_position.x, 40.0, 0.001)
	assert_almost_eq(host.global_position.y, 30.0, 0.001)

func test_wait_signal_waits_for_the_signal() -> void:
	var runner := _runner("wait_signal.xml")
	runner.start()
	await wait_frames(3)
	assert_true(runner.running)
	assert_eq(host.pings, 0, "the sequence must not pass wait_signal before the signal")
	host.drop_finished.emit()
	assert_eq(host.pings, 1)
	assert_false(runner.running)

func test_signal_trigger_starts_on_the_signal() -> void:
	var runner := _runner("signal_trigger.xml")
	runner.start()
	assert_eq(host.pings, 0, "a signal trigger waits for its signal")
	host.fired.emit()
	assert_eq(host.pings, 1)

func test_manual_trigger_runs_on_start() -> void:
	var runner := _runner("manual_trigger.xml")
	assert_eq(host.pings, 0, "attach without auto does not start")
	runner.start()
	assert_eq(host.pings, 1)

func test_missing_file_prints_an_error() -> void:
	allow_errors = true
	var runner := _runner("does_not_exist.xml")
	runner.start()
	assert_true(runner.sequence.is_empty())
	assert_false(runner.running)

func test_play_anim_finds_a_child_sprite() -> void:
	var body := AnimatedSprite2D.new()
	body.sprite_frames = _frames(&"idle")
	host.add_child(body)
	var visuals := Node2D.new()
	visuals.name = "Visuals"
	host.add_child(visuals)
	var eyes := AnimatedSprite2D.new()
	eyes.name = "Eyes"
	eyes.sprite_frames = _frames(&"blink")
	visuals.add_child(eyes)
	var runner := _runner("play_anim.xml")
	runner.start()
	assert_eq(body.animation, &"idle", "play_anim without node_path plays the first AnimatedSprite2D")
	assert_true(body.is_playing())
	assert_eq(eyes.animation, &"blink", "play_anim with node_path plays that sprite")
	assert_true(eyes.is_playing())

func test_call_start_chains_into_another_sequence() -> void:
	var runner := _runner("chain.xml")
	var finished: Array[int] = [0]
	runner.sequence_finished.connect(func() -> void: finished[0] += 1)
	runner.start()
	assert_eq(host.pings, 1, "the chained sequence runs once")
	assert_eq(finished[0], 1)

# The runner's later features, one fixture each.

func test_named_sections_run_separately() -> void:
	var path := DIR + "sections.xml"
	assert_eq(sequence_runner.sections(path), PackedStringArray(["first", "second"]))
	assert_true(sequence_runner.has_section(path, "second"))
	assert_false(sequence_runner.has_section(path, ""), "the file has no unnamed section")
	var runner := _runner("sections.xml")
	assert_true(runner.start(path, {}, "first"))
	assert_eq(host.rolls, [1, 1] as Array[int], "first loops twice to its own label")
	assert_true(runner.start(path, {}, "second"))
	assert_eq(host.rolls, [1, 1, 2] as Array[int], "second jumps to its own label")

func test_a_missing_section_does_not_run() -> void:
	allow_errors = true
	var runner := _runner("sections.xml")
	var finished: Array[int] = [0]
	runner.sequence_finished.connect(func() -> void: finished[0] += 1)
	assert_false(runner.start("", {}, "third"), "a missing section is refused")
	assert_false(runner.running)
	assert_eq(finished[0], 0, "sequence_finished is not emitted")
	assert_true(host.rolls.is_empty())
	assert_eq(sequence_runner.sections(DIR + "does_not_exist.xml"), PackedStringArray())

func test_a_seeded_object_is_called_waited_on_and_read() -> void:
	var body := Recorder.new()
	add_child(body)
	var runner := _runner("named_objects.xml")
	runner.start("", {"body": body})
	assert_eq(body.pings, 1, "on=\"body\" calls the object handed in")
	assert_eq(body.rolls, [7] as Array[int], "on=\"$body\" too, and $body.radius reads it")
	assert_true(runner.running, "wait_signal on=\"body\" waits for the body's signal")
	assert_false(runner.scratch_pad.has("target_body"), "a scratch-pad object is not cached")
	body.fired.emit()
	assert_eq(host.pings, 1)
	assert_false(runner.running)

## A Recorder standing for a board piece, its props {"health": 3}.
func _piece() -> Recorder:
	var piece := Recorder.new()
	piece.props = {"health": 3}
	add_child(piece)
	return piece

func test_a_dictionary_path_is_read() -> void:
	var stats: Dictionary = {"bonus": 2, "nested": {"deep": 5}}
	_runner("dict_paths.xml").start("", {"piece": _piece(), "stats": stats})
	assert_eq(host.rolls, [3, 2, 5] as Array[int], "$piece.props.health, $stats.bonus, $stats.nested.deep")

func test_a_missing_dictionary_key_is_an_error_and_the_sequence_goes_on() -> void:
	allow_errors = true
	var runner := _runner("dict_paths.xml")
	runner.start("", {"piece": _piece()}, "missing")
	assert_true(runner.scratch_pad.has("read"))
	assert_null(runner.scratch_pad["read"], "a missing key reads as null")
	assert_eq(host.pings, 1, "the sequence went on")

func test_set_prop_writes_a_property_a_key_and_a_vector_component() -> void:
	var body := Recorder.new()
	add_child(body)
	var piece := _piece()
	var stats: Dictionary = {"bonus": 1}
	_runner("set_prop.xml").start("", {"body": body, "piece": piece, "stats": stats})
	assert_eq(body.radius, 9, "a property")
	assert_almost_eq(float(piece.props["health"]), 2.0, 0.0001, "a key read and written by expr")
	assert_eq(piece.props.get("armor"), 2, "a missing key is created")
	assert_almost_eq(host.position.x, 12.5, 0.0001, "a Vector2 component of the target, written back")
	assert_eq(stats["bonus"], 4, "a scratch-pad dictionary's key")

func test_call_stores_a_return_and_awaits_a_signal_and_a_coroutine() -> void:
	var runner := _runner("call_returns.xml")
	runner.start()
	assert_eq(host.rolls, [2, 42] as Array[int], "var= stores the return; await on a plain value goes on")
	assert_true(runner.running, "await=\"true\" waits for the returned signal")
	assert_eq(host.pings, 0)
	host.fired.emit()
	assert_eq(host.pings, 1, "the signal let the sequence on")
	assert_true(runner.running, "await=\"true\" waits for the coroutine")
	host.drop_finished.emit()
	assert_eq(host.rolls, [2, 42, 5] as Array[int], "var= holds the coroutine's final return value")
	assert_false(runner.running)

func test_validate_lists_the_problems_without_printing_them() -> void:
	var runner := sequence_runner.new()
	var path := BROKEN_DIR + "broken.xml"
	assert_eq(runner.validate(path), PackedStringArray([
		path + ": a second section \"loop\" (ignored)",
		path + ":: unknown command <cal>",
		path + ":: <set> has no attribute \"valu\"",
		path + ":loop: <goto> to a label the section lacks: \"end\"",
	]), "an unknown command and attribute, a label only another section has, a duplicate section")
	assert_eq(runner.compile_errors, 4)
	var empty := BROKEN_DIR + "no_section.xml"
	assert_eq(runner.validate(empty), PackedStringArray([empty + ": no section (no <sequence> element)"]))
	var missing := BROKEN_DIR + "does_not_exist.xml"
	assert_eq(runner.validate(missing), PackedStringArray([missing + ": cannot be read"]))
	runner.free()

func test_every_fixture_validates() -> void:
	var runner := sequence_runner.new()
	for file: String in DirAccess.get_files_at(DIR):
		if file.get_extension() == "xml":
			assert_eq(runner.validate(DIR + file), PackedStringArray(), file)
	runner.free()

func test_a_compile_problem_is_an_error_when_started() -> void:
	allow_errors = true
	var runner := _runner("")
	runner.start(BROKEN_DIR + "broken.xml")
	assert_eq(runner.compile_errors, 2, "the unnamed section's unknown command and attribute")
	assert_eq(host.rolls, [1] as Array[int], "the sound commands still run")

## The rolls random_int.xml makes over ten starts with `rng` seeded `seed_value`.
func _seeded_rolls(seed_value: int) -> Array[int]:
	host.rolls.clear()
	var runner := _runner("random_int.xml")
	runner.rng = RandomNumberGenerator.new()
	runner.rng.seed = seed_value
	for i: int in 10:
		runner.start()
	runner.queue_free()
	return host.rolls.duplicate()

func test_a_seeded_rng_makes_random_int_reproducible() -> void:
	var first := _seeded_rolls(7)
	assert_eq(first.size(), 20)
	assert_eq(_seeded_rolls(7), first, "the same seed rolls the same")
	assert_ne(_seeded_rolls(8), first, "another seed rolls otherwise")

func test_true_is_a_bool_and_a_quoted_number_a_string() -> void:
	var runner := _runner("typed_values.xml")
	runner.start()
	assert_eq(host.taken.size(), 4)
	assert_eq(typeof(host.taken[0]), TYPE_BOOL, "true is a bool")
	assert_true(host.taken[0])
	assert_eq(typeof(host.taken[1]), TYPE_STRING, "'7' is a string")
	assert_eq(host.taken[1], "7")
	assert_eq(typeof(host.taken[2]), TYPE_BOOL, "FALSE is a bool")
	assert_false(host.taken[2])
	assert_eq(typeof(host.taken[3]), TYPE_INT, "7 is an int")
	assert_eq(typeof(runner.scratch_pad["flag"]), TYPE_BOOL, "set's value is typed too")
	assert_eq(runner.scratch_pad["code"], "12")

func test_stop_ends_a_looping_sequence_and_finishes_it_once() -> void:
	var runner := _runner("stop.xml")
	var finished: Array[int] = [0]
	runner.sequence_finished.connect(func() -> void: finished[0] += 1)
	runner.start("", {}, "loop")
	await wait_seconds(0.1)
	assert_true(runner.running, "the loop runs on")
	assert_gt(host.pings, 1)
	runner.stop()
	assert_false(runner.running)
	assert_true(runner.stopped, "stopped says it was cut")
	assert_eq(finished[0], 1, "sequence_finished fires at once")
	var pings := host.pings
	await wait_seconds(0.1)
	assert_eq(host.pings, pings, "no command runs after stop()")
	assert_eq(finished[0], 1, "sequence_finished fires once")
	runner.start("", {}, "loop")
	assert_false(runner.stopped, "start() clears stopped")
	runner.stop()

func test_stop_from_inside_the_sequence_and_free_while_waiting() -> void:
	var runner := _runner("stop.xml")
	runner.start("", {}, "self_stop")
	assert_eq(host.pings, 0, "the command after stop() does not run")
	assert_true(runner.stopped)
	var looping := _runner("stop.xml")
	looping.start("", {}, "loop")
	looping.stop()
	looping.free()
	await wait_seconds(0.1)
	assert_eq(host.pings, 1, "a runner stopped and freed while waiting plays nothing more")

func test_goto_if_compares_strings_with_eq_and_not_eq() -> void:
	var runner := _runner("goto_if_strings.xml")
	runner.start("", {"element": "fire"})
	assert_eq(host.rolls, [1] as Array[int], "fire eq fire jumps; fire != water jumps")
	host.rolls.clear()
	runner.start("", {"element": "water"})
	assert_eq(host.rolls, [0, 2] as Array[int], "water eq fire does not jump, nor water != water")

func test_goto_if_ordering_strings_is_an_error() -> void:
	allow_errors = true
	_runner("goto_if_strings.xml").start("", {"element": "fire"}, "bad")
	assert_eq(host.pings, 1, "no jump; the sequence went on")

## goto_if_aliases.xml's unnamed section on $a and $b: the numbers it records
## (1 lt, 2 gt, 3 le, 4 ge jumped).
func _aliases(a: Variant, b: Variant) -> Array[int]:
	host.rolls.clear()
	_runner("goto_if_aliases.xml").start("", {"a": a, "b": b})
	return host.rolls.duplicate()

func test_goto_if_aliases_compare_numbers() -> void:
	assert_eq(_aliases(1, 2), [1, 3] as Array[int], "1 lt 2, 1 le 2")
	assert_eq(_aliases(2, 1), [2, 4] as Array[int], "2 gt 1, 2 ge 1")
	assert_eq(_aliases(1, 1), [3, 4] as Array[int], "1 le 1, 1 ge 1; neither lt nor gt")
	assert_eq(_aliases(-1, 0), [1, 3] as Array[int], "-1 below 0 (the big slime's guard)")
	assert_eq(_aliases(0.5, "1"), [1, 3] as Array[int], "a float and a number token compare as numbers")

func test_goto_if_alias_ordering_strings_is_an_error() -> void:
	allow_errors = true
	_runner("goto_if_aliases.xml").start("", {"element": "fire"}, "strings")
	assert_eq(host.pings, 1, "lt on strings is the error > is: no jump; the sequence went on")

func test_goto_if_unknown_operator_is_an_error() -> void:
	allow_errors = true
	_runner("goto_if_aliases.xml").start("", {"a": -1}, "unknown")
	assert_eq(host.pings, 1, "an unknown operator does not jump; the sequence went on")

func test_a_run_time_problem_is_an_error_and_the_sequence_goes_on() -> void:
	allow_errors = true
	_runner("runtime_error.xml").start()
	assert_eq(host.pings, 1)

## expressions.xml's unnamed section started with its vars; the runner.
func _expressions() -> sequence_runner:
	var body := Recorder.new()
	add_child(body)
	body.global_position = Vector2(10, 20)
	var piece := _piece()
	piece.props["step"] = 2
	var runner := _runner("expressions.xml")
	runner.start("", {"a": 3, "b": 4, "flag": true, "period": 1.0, "i": 0, "text": "go",
		"num": "7", "element": "fire", "body": body, "piece": piece})
	return runner

func test_expressions_read_like_gdscript() -> void:
	var runner := _expressions()
	var pad := runner.scratch_pad
	assert_almost_eq(float(pad["p"]), 14.0, 0.0001, "parentheses")
	assert_almost_eq(float(pad["q"]), 11.0, 0.0001, "precedence")
	assert_almost_eq(float(pad["r"]), 4.0, 0.0001, "no spaces needed")
	assert_almost_eq(float(pad["s"]), 7.0, 0.0001, "abs, clamp, min")
	assert_almost_eq(float(pad["t"]), 11.0, 0.0001, "a path into a seeded object")
	assert_almost_eq(float(pad["u"]), 2.0, 0.0001, "a bool adds as 1")
	assert_almost_eq(float(pad["v"]), 0.5, 0.0001, "a float divided by an int literal")
	assert_true(pad["w"] is float, "an int reference reads as a float, as every command's number")
	assert_almost_eq(float(pad["w"]), 1.0, 0.0001)
	assert_eq(pad["x"], "go!", "strings concatenate; a literal in single quotes")
	assert_eq(pad["y"], "big", "a ternary")
	assert_eq(pad["z"], "Node2D", "a method called on a seeded object")
	assert_almost_eq(float(pad["seven"]), 7.0, 0.0001, "a string that reads as a number is one")
	assert_eq(pad["hot"], true, "a comparison gives a bool")
	assert_eq(host.pings, 0, "goto_if jumped on it")
	var piece: Recorder = pad["piece"]
	assert_almost_eq(float(piece.props["health"]), 1.0, 0.0001, "set_prop with a two-term expression")

func test_evaluate_expr_from_code() -> void:
	var runner := _runner("expressions.xml")
	runner.scratch_pad = {"a": 2}
	assert_almost_eq(float(runner.evaluate_expr("$a * 3 + 1")), 7.0, 0.0001)

## The rolls expressions.xml's `random` section makes over five starts, `rng` seeded.
func _expression_rolls(seed_value: int) -> Array[int]:
	host.rolls.clear()
	var runner := _runner("expressions.xml")
	runner.rng = RandomNumberGenerator.new()
	runner.rng.seed = seed_value
	for i: int in 5:
		runner.start("", {}, "random")
	runner.queue_free()
	return host.rolls.duplicate()

func test_random_int_inside_an_expression_rolls_on_the_seeded_rng() -> void:
	var first := _expression_rolls(7)
	assert_eq(first.size(), 10)
	for roll: int in first:
		assert_true(roll >= 11 and roll <= 66 and roll % 10 >= 1 and roll % 10 <= 6, str(roll))
	assert_eq(_expression_rolls(7), first, "the same seed rolls the same")
	assert_ne(_expression_rolls(8), first, "another seed rolls otherwise")

func test_expression_failures_are_errors_and_read_as_zero() -> void:
	allow_errors = true
	var runner := _runner("expressions.xml")
	var body := Recorder.new()
	add_child(body)
	runner.start("", {"a": 3, "body": body}, "errors")
	var pad := runner.scratch_pad
	assert_almost_eq(float(pad["d"]), 0.0, 0.0001, "a float divided by zero is an error, not inf")
	assert_almost_eq(float(pad["e"]), 0.0, 0.0001, "an int divided by zero")
	assert_almost_eq(float(pad["f"]), 0.0, 0.0001, "a string plus a number")
	assert_almost_eq(float(pad["g"]), 0.0, 0.0001, "an unknown function")
	assert_almost_eq(float(pad["h"]), 0.0, 0.0001, "a member the Expression cannot read")
	assert_almost_eq(float(pad["k"]), 1.0, 0.0001, "an unresolvable reference reads as 0, the one error it is today")
	assert_eq(host.pings, 1, "the sequence went on")

func test_a_malformed_expression_is_a_compile_problem() -> void:
	var runner := sequence_runner.new()
	var path := BROKEN_DIR + "expressions.xml"
	var problems := runner.validate(path)
	assert_eq(problems.size(), 2, str(problems))
	assert_true(problems[0].begins_with(path + ":: <set> expr \"1 +\": "), problems[0])
	assert_true(problems[1].begins_with(path + ":: <set_prop> expr \"($a\": "), problems[1])
	runner.free()
	allow_errors = true
	var started := _runner("")
	started.start(path)
	assert_eq(started.compile_errors, 2, "start() pushes them")
	assert_false(started.scratch_pad.has("a"), "the command did nothing")
	assert_eq(host.pings, 1, "the sound commands still run")
