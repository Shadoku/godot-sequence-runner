extends TestCase
## max_instant_steps: a sequence that runs more commands than this without
## waiting is stopped with an error and `failed`, whatever stop_on_error says,
## instead of hanging the game. The count restarts each time the sequence waits.
## 0 disables the cap. Fixture: max_instant_steps.xml.

const FILE: String = "res://fixtures/sequences/max_instant_steps.xml"

## The node a runner drives: counts its pings.
class Pinged extends Node2D:
	var pings: int = 0

	func ping() -> void:
		pings += 1

var host: Pinged
var finished: Array[int] = [0]

func before_each() -> void:
	host = Pinged.new()
	add_child(host)
	finished = [0]

## A runner on the host for max_instant_steps.xml capped at `cap`, its
## sequence_finished counted in `finished`.
func _runner(cap: int) -> sequence_runner:
	var runner := sequence_runner.attach(host, FILE)
	runner.max_instant_steps = cap
	runner.sequence_finished.connect(func() -> void: finished[0] += 1)
	return runner

## Checks that `runner` was stopped by the cap: failed, stopped, finished once.
func _assert_capped(runner: sequence_runner) -> void:
	assert_true(runner.failed, "failed")
	assert_true(runner.stopped, "stopped")
	assert_false(runner.running, "not running")
	assert_eq(finished[0], 1, "sequence_finished emitted once")

func test_max_instant_steps_defaults_to_100000() -> void:
	var runner := sequence_runner.new()
	assert_eq(runner.max_instant_steps, 100000)
	runner.free()

func test_a_loop_that_never_waits_is_stopped_with_an_error() -> void:
	allow_errors = true
	var runner := _runner(50)
	assert_false(runner.stop_on_error, "the cap applies with stop_on_error off")
	runner.start("", {}, "spin")
	_assert_capped(runner)

func test_the_default_cap_stops_a_loop_that_never_waits() -> void:
	allow_errors = true
	var runner := sequence_runner.attach(host, FILE)
	var ok: bool = await runner.start_and_wait("", {}, "spin")
	assert_true(ok)
	assert_true(runner.failed)
	assert_true(runner.stopped)

func test_commands_up_to_the_cap_run() -> void:
	var runner := _runner(5)
	runner.start("", {}, "five")
	assert_eq(host.pings, 5)
	assert_false(runner.failed)
	assert_false(runner.stopped)

func test_the_command_past_the_cap_does_not_run() -> void:
	allow_errors = true
	var runner := _runner(4)
	runner.start("", {}, "five")
	assert_eq(host.pings, 4)
	_assert_capped(runner)

func test_instant_commands_below_the_default_cap_are_unaffected() -> void:
	var runner := sequence_runner.attach(host, FILE)
	runner.start("", {}, "counted")
	assert_almost_eq(float(runner.scratch_pad["i"]), 200.0, 0.0001)
	assert_false(runner.failed)
	assert_false(runner.stopped)

func test_zero_disables_the_cap() -> void:
	var runner := _runner(0)
	runner.start("", {}, "counted")
	assert_almost_eq(float(runner.scratch_pad["i"]), 200.0, 0.0001, "401 commands ran")
	assert_false(runner.failed)

func test_the_count_restarts_when_the_sequence_waits() -> void:
	var runner := _runner(4)
	var ok: bool = await runner.start_and_wait("", {}, "chunks")
	assert_true(ok)
	assert_eq(host.pings, 9, "4, 4 and 3 commands between waits, 11 in all")
	assert_false(runner.failed)
	assert_false(runner.stopped)

func test_a_wait_counts_as_a_command_before_it_waits() -> void:
	allow_errors = true
	var runner := _runner(3)
	runner.start("", {}, "chunks")
	assert_eq(host.pings, 3, "the wait would have been the fourth command")
	_assert_capped(runner)
