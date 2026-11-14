extends TestCase
## Sub-sequences: `<run section file var />` runs a section on a child runner
## (an instance of the caller's script, with a shallow copy of its scratch pad)
## and waits for it; `run_once()` runs a section on a temporary runner.
## Fixtures: tests/fixtures/sequences/run*.xml, tests/fixtures/broken_sequences/run.xml.

const DIR: String = "res://fixtures/sequences/"
const FILE: String = "res://fixtures/sequences/run.xml"
const BROKEN: String = "res://fixtures/broken_sequences/run.xml"

## The node a runner drives: records what its sequences do to it.
class Recorder extends Node2D:
	signal fired

	var pings: int = 0
	var score: int = 0
	var rolls: Array = []
	var noted: Array[Dictionary] = []

	func ping() -> void:
		pings += 1

	func record(value: Variant) -> void:
		rolls.append(value)

	## Notes what the runner `runner` (a child, from inside its section) is.
	func note_runner(runner: sequence_runner) -> void:
		noted.append({
			"runner": runner,
			"script": runner.get_script(),
			"parent": runner.get_parent(),
			"target": runner.target,
			"rng": runner.rng,
			"verbose": runner.verbose,
			"stop_on_error": runner.stop_on_error,
			"max_instant_steps": runner.max_instant_steps,
		})

## A runner whose <stop> is its own: it records 99 on the target and goes on.
class OwnStopRunner extends sequence_runner:
	func register_commands() -> void:
		super.register_commands()
		register_command("stop", factory_own_stop, PackedStringArray())

	func factory_own_stop(_args: Dictionary, _index: int) -> Callable:
		return func() -> Variant:
			target.call("record", 99)
			return null

## A runner that stops at its first run-time error.
class StrictRunner extends sequence_runner:
	func _init() -> void:
		stop_on_error = true

var host: Recorder
var finished: Array[int] = [0]

func before_each() -> void:
	host = Recorder.new()
	add_child(host)
	finished = [0]

## A runner on the host for run.xml, its sequence_finished counted in `finished`.
func _runner(on_error: bool = false) -> sequence_runner:
	var runner := sequence_runner.attach(host, FILE)
	runner.stop_on_error = on_error
	runner.sequence_finished.connect(func() -> void: finished[0] += 1)
	return runner

## The sequence runners among `node`'s children.
func _runners_under(node: Node) -> Array[sequence_runner]:
	var found: Array[sequence_runner] = []
	for child: Node in node.get_children():
		if child is sequence_runner:
			found.append(child as sequence_runner)
	return found

func test_max_run_depth_is_32() -> void:
	assert_eq(sequence_runner.MAX_RUN_DEPTH, 32)

func test_an_instant_run_finishes_inside_start() -> void:
	var runner := _runner()
	assert_true(runner.start("", {}, "instant"))
	assert_eq(host.rolls, [1, 2, 3], "the child ran in place, no frame passed")
	assert_false(runner.running)
	assert_false(runner.failed)
	assert_eq(finished[0], 1, "sequence_finished once, inside start()")
	assert_eq(_runners_under(runner), [] as Array[sequence_runner], "the child is freed at once")

func test_run_plays_a_section_of_another_file() -> void:
	_runner().start("", {}, "other_file")
	assert_eq(host.rolls, [5, 6])

func test_run_waits_for_an_async_child() -> void:
	var runner := _runner()
	runner.start("", {}, "async")
	assert_eq(host.rolls, [1], "the caller waits for the child")
	assert_true(runner.running)
	var children := _runners_under(runner)
	assert_eq(children.size(), 1, "the child is the caller's child while it runs")
	assert_true(children[0].running)
	assert_true(await await_signal(runner.sequence_finished, 2.0))
	assert_eq(host.rolls, [1, 2, 3])
	assert_eq(finished[0], 1)
	await wait_frames(1)
	assert_false(is_instance_valid(children[0]), "the child is freed when done")

func test_start_and_wait_waits_for_a_run_child() -> void:
	var runner := _runner()
	var ok: bool = await runner.start_and_wait("", {}, "async")
	assert_true(ok)
	assert_eq(host.rolls, [1, 2, 3])

func test_a_stop_in_the_child_ends_only_the_child() -> void:
	var runner := _runner()
	runner.start("", {}, "calls_stops")
	assert_eq(host.rolls, [1])
	assert_false(runner.stopped)
	assert_false(runner.failed)

func test_the_child_is_an_instance_of_the_callers_script() -> void:
	var runner := OwnStopRunner.new()
	host.add_child(runner)
	runner.start(FILE, {}, "calls_stops")
	assert_eq(host.rolls, [99, 2, 1], "the subclass's own <stop> ran in the child")

func test_the_child_inherits_the_callers_settings() -> void:
	var runner := OwnStopRunner.new()
	var dice := RandomNumberGenerator.new()
	runner.rng = dice
	runner.verbose = true
	runner.stop_on_error = true
	runner.max_instant_steps = 77
	host.add_child(runner)
	runner.start(FILE, {}, "notes")
	assert_eq(host.noted.size(), 1)
	var seen: Dictionary = host.noted[0]
	assert_ne(seen["runner"], runner, "a child runner ran the section")
	assert_eq(seen["script"], runner.get_script())
	assert_eq(seen["parent"], runner)
	assert_eq(seen["target"], host)
	assert_eq(seen["rng"], dice)
	assert_eq(seen["verbose"], true)
	assert_eq(seen["stop_on_error"], true)
	assert_eq(seen["max_instant_steps"], 77)

func test_the_child_gets_a_shallow_copy_of_the_scratch_pad() -> void:
	var shared: Dictionary = {"hp": 3}
	var runner := _runner()
	runner.start("", {"shared": shared}, "shallow")
	assert_eq(host.rolls, [1, 1], "the child reads the caller's $n; its own set does not leak back")
	assert_eq(runner.scratch_pad["n"], 1)
	assert_eq(shared["hp"], 5, "a shared dictionary is written through")
	assert_eq(host.score, 7, "an object is written through")

func test_var_receives_the_childs_result() -> void:
	var runner := _runner()
	runner.start("", {}, "results")
	assert_almost_eq(float(runner.scratch_pad["out"]), 6.0, 0.0001)
	assert_true(runner.scratch_pad.has("none"))
	assert_null(runner.scratch_pad["none"], "null when the child set no $result, even when the caller has one")
	assert_eq(runner.scratch_pad["result"], 7, "the caller's own $result is untouched")

func test_run_ignores_the_files_trigger() -> void:
	_runner().start("", {}, "trigger_caller")
	assert_eq(host.rolls, [1], "ran at once, without the signal")

func test_start_on_a_file_with_a_trigger_is_unchanged() -> void:
	var runner := sequence_runner.attach(host, DIR + "run_trigger.xml")
	runner.start()
	assert_eq(host.rolls, [], "the signal trigger defers it, as before")
	host.fired.emit()
	assert_eq(host.rolls, [1])

func test_a_child_of_the_same_file_leaves_the_callers_state_alone() -> void:
	var runner := _runner()
	runner.start("", {}, "keeps_state")
	assert_true(runner.running)
	assert_eq(runner.current_section, "keeps_state")
	assert_eq(runner.labels, {"again": 1})
	assert_eq(runner.index, 3)
	assert_eq(runner.sequence.size(), 6)
	assert_eq(runner.xml_path, FILE)
	assert_true(await await_signal(runner.sequence_finished, 2.0))
	assert_eq(host.rolls, [2.0], "the caller's goto used its own labels: two rounds")

func test_file_and_section_can_be_references() -> void:
	_runner().start("", {"f": DIR + "run_other.xml", "s": "other"}, "dynamic")
	assert_eq(host.rolls, [5])

func test_stop_stops_the_running_child() -> void:
	var runner := _runner()
	runner.start("", {}, "async")
	var child: sequence_runner = _runners_under(runner)[0]
	runner.stop()
	assert_false(runner.running)
	assert_true(runner.stopped)
	assert_eq(finished[0], 1)
	assert_false(child.running, "the child was stopped")
	assert_true(child.stopped)
	await wait_frames(2)
	assert_false(is_instance_valid(child), "and freed")
	assert_eq(host.rolls, [1])

func test_a_failed_child_fails_the_caller_with_stop_on_error() -> void:
	allow_errors = true
	var runner := _runner(true)
	runner.start("", {}, "calls_failing")
	assert_eq(host.rolls, [], "nothing ran after the child's error")
	assert_true(runner.failed)
	assert_true(runner.stopped)
	assert_false(runner.running)
	assert_eq(finished[0], 1)

func test_a_failed_child_does_not_stop_the_caller_without_stop_on_error() -> void:
	allow_errors = true
	var runner := _runner(false)
	runner.max_instant_steps = 50
	runner.start("", {}, "calls_spin")
	assert_eq(host.rolls, [3], "the child failed (its own max_instant_steps); the caller carried on")
	assert_false(runner.failed)
	assert_false(runner.stopped)

func test_max_instant_steps_in_a_child_fails_the_caller_with_stop_on_error() -> void:
	allow_errors = true
	var runner := _runner(true)
	runner.max_instant_steps = 50
	runner.start("", {}, "calls_spin")
	assert_eq(host.rolls, [])
	assert_true(runner.failed)
	assert_eq(finished[0], 1)

func test_a_section_that_runs_itself_stops_at_the_depth_cap() -> void:
	allow_errors = true
	var runner := _runner(false)
	runner.start("", {}, "recurse")
	assert_eq(host.pings, sequence_runner.MAX_RUN_DEPTH + 1, "the caller and 32 nested children")
	assert_false(runner.running)
	assert_eq(finished[0], 1)
	assert_eq(_runners_under(runner), [] as Array[sequence_runner])

func test_the_depth_cap_fails_the_run_with_stop_on_error() -> void:
	allow_errors = true
	var runner := _runner(true)
	runner.start("", {}, "recurse")
	assert_eq(host.pings, sequence_runner.MAX_RUN_DEPTH + 1)
	assert_true(runner.failed)
	assert_eq(finished[0], 1)

func test_the_depth_cap_stops_recursion_under_a_small_max_instant_steps() -> void:
	allow_errors = true
	var runner := _runner(false)
	runner.max_instant_steps = 3
	runner.start("", {}, "recurse")
	assert_eq(host.pings, sequence_runner.MAX_RUN_DEPTH + 1, "each child counts its own steps")
	assert_false(runner.failed)

func test_validate_lists_a_missing_section() -> void:
	var runner := sequence_runner.new()
	assert_eq(runner.validate(BROKEN), PackedStringArray([
		BROKEN + ":: <run>: " + BROKEN + " has no section \"nope\"",
		BROKEN + ":: <run>: " + DIR + "run_other.xml has no section \"nope\"",
	]))
	runner.free()

func test_a_missing_section_at_run_time_is_an_error() -> void:
	allow_errors = true
	var runner := _runner(false)
	runner.start("", {"name": "nope"}, "missing_at_run")
	assert_eq(host.rolls, [1], "nothing ran; the caller went on")
	runner = _runner(true)
	finished = [0]
	runner.start("", {"name": "nope"}, "missing_at_run")
	assert_true(runner.failed)
	assert_eq(host.rolls, [1])
	assert_eq(finished[0], 1)

func test_no_child_runs_after_a_failed_operand() -> void:
	allow_errors = true
	var runner := _runner(true)
	runner.start("", {}, "bad_operand")
	assert_eq(host.rolls, [], "the section \"two\" did not run")
	assert_true(runner.failed)
	assert_eq(_runners_under(runner), [] as Array[sequence_runner])

func test_run_once_plays_an_instant_section() -> void:
	var ok: bool = await sequence_runner.run_once(host, FILE, {}, "two")
	assert_true(ok)
	assert_eq(host.rolls, [2])
	assert_eq(_runners_under(host), [] as Array[sequence_runner], "its runner is freed at once")

func test_run_once_waits_for_an_async_section() -> void:
	var ok: bool = await sequence_runner.run_once(host, FILE, {}, "waits")
	assert_true(ok)
	assert_eq(host.rolls, [2])
	await wait_frames(1)
	assert_eq(_runners_under(host), [] as Array[sequence_runner], "its runner is freed")

func test_run_once_passes_vars() -> void:
	var shared: Dictionary = {"hp": 3}
	var ok: bool = await sequence_runner.run_once(host, FILE, {"n": 9, "shared": shared}, "writes")
	assert_true(ok)
	assert_eq(host.rolls, [9])
	assert_eq(shared["hp"], 5)

func test_run_once_returns_false_for_a_missing_section() -> void:
	allow_errors = true
	var ok: bool = await sequence_runner.run_once(host, FILE, {}, "nope")
	assert_false(ok)
	assert_eq(_runners_under(host), [] as Array[sequence_runner])

func test_run_once_returns_false_when_the_run_failed() -> void:
	allow_errors = true
	var ok: bool = await sequence_runner.run_once(host, FILE, {}, "fails", StrictRunner)
	assert_false(ok)
	assert_eq(host.rolls, [])
	await wait_frames(1)
	assert_eq(_runners_under(host), [] as Array[sequence_runner])

func test_run_once_uses_the_runner_script() -> void:
	var ok: bool = await sequence_runner.run_once(host, FILE, {}, "stops", OwnStopRunner)
	assert_true(ok)
	assert_eq(host.rolls, [99, 2])

func test_run_once_ignores_the_trigger() -> void:
	var ok: bool = await sequence_runner.run_once(host, DIR + "run_trigger.xml")
	assert_true(ok)
	assert_eq(host.rolls, [1])

func test_run_once_returns_false_when_the_host_is_freed() -> void:
	var other := Recorder.new()
	add_child(other)
	var result: Array = [null]
	var waiter := func() -> void:
		result[0] = await sequence_runner.run_once(other, FILE, {}, "waits")
	waiter.call()
	assert_null(result[0], "still running")
	other.free()
	await wait_frames(2)
	assert_eq(result[0], false)
