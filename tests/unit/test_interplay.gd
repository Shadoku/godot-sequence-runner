extends TestCase
## Features built in separate branches, used together: blocks with
## stop_on_error, <stop/> and max_instant_steps, and <run> with blocks,
## max_instant_steps and start_and_wait(). Fixture: interplay.xml.

const FILE: String = "res://fixtures/sequences/interplay.xml"

## The node a runner drives: records what its sequences do to it.
class Recorder extends Node2D:
	var pings: int = 0
	var rolls: Array = []
	var runner_ids: Array[int] = []

	func ping() -> void:
		pings += 1

	func record(value: Variant) -> void:
		rolls.append(value)

	## Notes which runner (a <run> child) called it.
	func note(runner: sequence_runner) -> void:
		runner_ids.append(runner.get_instance_id())

var host: Recorder
var finished: Array[int] = [0]

func before_each() -> void:
	host = Recorder.new()
	add_child(host)
	finished = [0]

## A runner on the host for interplay.xml, its sequence_finished counted in
## `finished`.
func _runner(on_error: bool = false, cap: int = 100000) -> sequence_runner:
	var runner := sequence_runner.attach(host, FILE)
	runner.stop_on_error = on_error
	runner.max_instant_steps = cap
	runner.sequence_finished.connect(func() -> void: finished[0] += 1)
	return runner

## Checks that `runner` failed and stopped, sequence_finished emitted once.
func _assert_failed(runner: sequence_runner) -> void:
	assert_true(runner.failed, "failed")
	assert_true(runner.stopped, "stopped")
	assert_false(runner.running, "not running")
	assert_eq(finished[0], 1, "sequence_finished emitted once")

## An array of `n` ints from 0.
func _range(n: int) -> Array:
	var list: Array = []
	for i: int in range(n):
		list.append(i)
	return list

func test_an_error_in_a_for_each_body_ends_the_loop_with_stop_on_error() -> void:
	allow_errors = true
	var runner := _runner(true)
	runner.start("", {"list": [1, 2, 3]}, "error_in_for_each")
	assert_eq(host.rolls, [1], "no further round, nothing after the loop")
	_assert_failed(runner)

func test_an_error_in_an_if_body_stops_the_run_with_stop_on_error() -> void:
	allow_errors = true
	var runner := _runner(true)
	runner.start("", {}, "error_in_if")
	assert_eq(host.rolls, [])
	_assert_failed(runner)

func test_an_error_in_an_if_expr_stops_the_run_with_stop_on_error() -> void:
	allow_errors = true
	var runner := _runner(true)
	runner.start("", {}, "error_in_if_expr")
	assert_eq(host.rolls, [], "neither branch ran")
	_assert_failed(runner)

func test_stop_in_a_for_each_ends_the_sequence() -> void:
	var runner := _runner()
	runner.start("", {"list": [1, 2, 3]}, "stop_in_for_each")
	assert_eq(host.rolls, [1, 2])
	assert_true(runner.stopped)
	assert_false(runner.failed)
	assert_eq(finished[0], 1)

func test_max_instant_steps_trips_inside_a_for_each_over_a_large_array() -> void:
	allow_errors = true
	var runner := _runner(false, 100)
	runner.start("", {"list": _range(1000)}, "big_loop")
	assert_eq(host.pings, 50, "the for_each, then ping and end marker per round: 100 commands")
	assert_eq(host.rolls, [])
	_assert_failed(runner)

func test_max_instant_steps_in_a_run_child_loop_without_stop_on_error() -> void:
	allow_errors = true
	var runner := _runner(false, 100)
	runner.start("", {"list": _range(1000)}, "run_big_loop")
	assert_eq(host.pings, 50, "the child got the caller's cap")
	assert_eq(host.rolls, ["after"], "the caller carried on")
	assert_false(runner.failed)

func test_max_instant_steps_in_a_run_child_loop_with_stop_on_error() -> void:
	allow_errors = true
	var runner := _runner(true, 100)
	runner.start("", {"list": _range(1000)}, "run_big_loop")
	assert_eq(host.pings, 50)
	assert_eq(host.rolls, [])
	_assert_failed(runner)

func test_the_callers_count_holds_its_run_commands_not_the_childs() -> void:
	allow_errors = true
	var runner := _runner(false, 50)
	runner.start("", {"list": _range(30)}, "runs_ten")
	assert_eq(host.pings, 250, "25 runs of 10 pings: each child counted its own 10")
	_assert_failed(runner)

func test_run_in_a_for_each_plays_one_child_per_round() -> void:
	var runner := _runner()
	runner.start("", {"list": [1, 2, 3]}, "run_in_for_each")
	assert_eq(host.rolls, [1, 10.0, 2, 20.0, 3, 30.0, 3, 2], "each child saw its round's $m; the child's sets did not reach the loop")
	assert_eq(host.runner_ids.size(), 3)
	assert_ne(host.runner_ids[0], host.runner_ids[1], "a new child per round")
	assert_ne(host.runner_ids[1], host.runner_ids[2])
	assert_false(runner.failed)
	assert_eq(finished[0], 1)

func test_start_and_wait_on_a_for_each_of_waiting_run_children() -> void:
	var runner := _runner()
	var ok: bool = await runner.start_and_wait("", {"list": [1, 2]}, "async_run_in_for_each")
	assert_true(ok)
	assert_eq(host.rolls, [10.0, 20.0])
	assert_false(runner.running)
	assert_eq(finished[0], 1)

func test_a_for_each_inside_a_run_child() -> void:
	var runner := _runner()
	runner.start("", {"list": [1, 2, 3]}, "run_child_loop")
	assert_eq(host.rolls, [1, 2, 3, 3])
	assert_false(runner.scratch_pad.has("m"), "the child's loop variable stays in the child")

func test_loops_at_the_same_index_in_caller_and_child_are_apart() -> void:
	var runner := _runner()
	runner.start("", {"list": [1, 2]}, "nested_loops")
	assert_eq(host.rolls, [1, 2, 1, 2])

func test_stop_in_a_for_each_in_a_child_ends_only_the_child() -> void:
	var runner := _runner()
	runner.start("", {"list": [1, 2, 3]}, "run_stop_in_for_each")
	assert_eq(host.rolls, [1, 2, "after"])
	assert_false(runner.stopped)

func test_an_error_in_a_child_for_each_fails_the_caller_with_stop_on_error() -> void:
	allow_errors = true
	var runner := _runner(true)
	runner.start("", {"list": [1, 2, 3]}, "run_error_in_for_each")
	assert_eq(host.rolls, [1])
	_assert_failed(runner)
