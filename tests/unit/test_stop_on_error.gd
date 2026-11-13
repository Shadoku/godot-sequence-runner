extends TestCase
## stop_on_error, failed and <stop/>. Off (the default) a run-time error is
## reported and the sequence carries on, as before; on, the first one sets
## `failed` and stops the sequence, and the command that met it has no side
## effect. <stop/> stops the sequence without failing it.
## Fixture: stop_on_error.xml.

const FILE: String = "res://fixtures/sequences/stop_on_error.xml"

## The node a runner drives: records what its sequences do to it.
class Recorder extends Node2D:
	signal fired

	var pings: int = 0
	var props: Dictionary = {"health": 3}
	var taken: Array = []

	func ping() -> void:
		pings += 1

	func take(value: Variant) -> void:
		taken.append(value)

## A runner whose <stop> command is its own (registered after the built-ins).
class OwnStopRunner extends sequence_runner:
	var own_stops: int = 0

	func register_commands() -> void:
		super.register_commands()
		register_command("stop", factory_own_stop, PackedStringArray())

	func factory_own_stop(_args: Dictionary, _index: int) -> Callable:
		return func() -> Variant:
			own_stops += 1
			return null

var host: Recorder
var finished: Array[int] = [0]

func before_each() -> void:
	host = Recorder.new()
	host.global_position = Vector2(1, 1)
	add_child(host)
	finished = [0]

func after_each() -> void:
	get_tree().paused = false

## A runner on the host for stop_on_error.xml, `stop_on_error` as given, its
## sequence_finished counted in `finished`.
func _runner(on: bool) -> sequence_runner:
	var runner := sequence_runner.attach(host, FILE)
	runner.stop_on_error = on
	runner.sequence_finished.connect(func() -> void: finished[0] += 1)
	return runner

## Plays `section` with stop_on_error on and checks that it failed and stopped
## at the first command, sequence_finished emitted once; returns the runner.
func _failed_run(section: String, vars: Dictionary = {}) -> sequence_runner:
	allow_errors = true
	var runner := _runner(true)
	runner.start("", vars, section)
	assert_true(runner.failed, section + ": failed")
	assert_true(runner.stopped, section + ": stopped")
	assert_false(runner.running, section + ": not running")
	assert_eq(finished[0], 1, section + ": sequence_finished emitted once")
	assert_eq(host.pings, 0, section + ": nothing runs after the error")
	return runner

func test_stop_on_error_defaults_off_and_failed_false() -> void:
	var runner := sequence_runner.new()
	assert_false(runner.stop_on_error)
	assert_false(runner.failed)
	runner.free()

func test_stop_on_error_off_carries_on_as_before() -> void:
	allow_errors = true
	var runner := _runner(false)
	runner.start("", {}, "two_errors")
	assert_eq(host.taken, [null, null], "both calls ran with the unresolvable argument")
	assert_eq(host.pings, 1, "the sequence went on")
	assert_false(runner.failed)
	assert_false(runner.stopped)
	assert_eq(finished[0], 1)

func test_stop_on_error_off_keeps_each_commands_side_effect() -> void:
	allow_errors = true
	var runner := _runner(false)
	runner.start("", {}, "set")
	assert_true(runner.scratch_pad.has("a"), "set wrote")
	assert_null(runner.scratch_pad["a"])
	runner.start("", {}, "set_expr")
	assert_almost_eq(float(runner.scratch_pad["a"]), 1.0, 0.0001, "set expr wrote")
	runner.start("", {}, "set_prop")
	assert_null(host.props["health"], "set_prop wrote")
	runner.start("", {}, "move")
	assert_eq(host.global_position, Vector2(0, 5), "move moved")
	runner.start("", {}, "goto_if")
	assert_eq(host.taken, [], "goto_if jumped (random(1) reads as 0)")
	assert_eq(host.pings, 5)
	assert_false(runner.failed)

func test_call_does_not_call_after_an_error() -> void:
	_failed_run("call")
	assert_eq(host.taken, [], "the method was not called")

func test_the_first_error_stops_the_run() -> void:
	_failed_run("two_errors")
	assert_eq(host.taken, [])

func test_set_does_not_write_after_an_error() -> void:
	var runner := _failed_run("set")
	assert_false(runner.scratch_pad.has("a"))
	runner = _runner(true)
	finished = [0]
	runner.start("", {}, "set_expr")
	assert_true(runner.failed)
	assert_false(runner.scratch_pad.has("a"), "nor with expr")

func test_set_prop_does_not_write_after_an_error() -> void:
	_failed_run("set_prop")
	assert_eq(host.props["health"], 3)
	finished = [0]
	_failed_run("set_prop_expr")
	assert_eq(host.props["health"], 3, "nor with expr")

func test_move_and_tween_move_do_not_move_after_an_error() -> void:
	_failed_run("move")
	assert_eq(host.global_position, Vector2(1, 1))
	finished = [0]
	_failed_run("tween_move")
	await wait_frames(3)
	assert_eq(host.global_position, Vector2(1, 1), "no tween was made")

func test_goto_if_does_not_jump_after_an_error() -> void:
	var runner := _failed_run("goto_if")
	assert_eq(runner.index, 1, "the index stays past the goto_if, not at the label")

func test_wait_pause_and_wait_signal_stop_after_an_error() -> void:
	_failed_run("wait")
	finished = [0]
	_failed_run("pause")
	assert_false(get_tree().paused, "pause did not pause the tree")
	finished = [0]
	var gone := Node.new()
	gone.free()
	_failed_run("wait_signal", {"gone": gone})

func test_an_error_while_waiting_stops_the_run() -> void:
	allow_errors = true
	var runner := _runner(true)
	runner.start("", {}, "waiting")
	assert_true(runner.running)
	runner.evaluate_expr("$missing")
	assert_true(runner.failed)
	assert_true(runner.stopped)
	assert_false(runner.running)
	assert_eq(finished[0], 1)
	host.fired.emit()
	assert_eq(host.pings, 0, "the abandoned wait does not resume")

func test_start_clears_failed() -> void:
	var runner := _failed_run("call")
	runner.start("", {}, "clean")
	assert_false(runner.failed)
	assert_false(runner.stopped)
	assert_eq(host.pings, 1)

func test_the_stop_command_stops_without_failing() -> void:
	var runner := _runner(false)
	runner.start("", {}, "stop")
	assert_eq(host.pings, 1, "the command after <stop/> does not run")
	assert_true(runner.stopped)
	assert_false(runner.failed)
	assert_false(runner.running)
	assert_eq(finished[0], 1)

func test_a_subclass_stop_command_wins_over_the_built_in() -> void:
	var runner := OwnStopRunner.new()
	host.add_child(runner)
	runner.start(FILE, {}, "stop")
	assert_eq(runner.own_stops, 1)
	assert_eq(host.pings, 2, "its own <stop> did not stop the sequence")
	assert_false(runner.stopped)
