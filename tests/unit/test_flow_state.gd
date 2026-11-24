extends TestCase
## flow_state() hands out the running section's for_each loops and open gosubs,
## and set_flow_state() puts a state back ({}: none), so a subclass that plays
## another section in the same runner can set the caller's aside.
## Fixture: flow_state.xml.

const FILE: String = "res://fixtures/sequences/flow_state.xml"

class Recorder extends Node2D:
	signal fired

	var pings: int = 0

	func ping() -> void:
		pings += 1

var host: Recorder
var runner: sequence_runner

func before_each() -> void:
	host = Recorder.new()
	add_child(host)
	runner = sequence_runner.attach(host, FILE)

func test_an_open_gosub_set_aside_is_not_returned_from() -> void:
	allow_errors = true
	runner.start("", {}, "gosub")
	runner.set_flow_state({})
	host.fired.emit()
	assert_eq(host.pings, 0, "<return/> found no gosub and the section ran on to its end")
	assert_false(runner.running)

func test_an_open_gosub_put_back_is_returned_from() -> void:
	runner.start("", {}, "gosub")
	var state: Dictionary = runner.flow_state()
	runner.set_flow_state({})
	runner.set_flow_state(state)
	host.fired.emit()
	assert_eq(host.pings, 1)

func test_a_loop_set_aside_ends_after_its_round() -> void:
	runner.start("", {"list": [1, 2, 3]}, "loop")
	runner.set_flow_state({})
	host.fired.emit()
	assert_eq(host.pings, 1)
	assert_false(runner.running)

func test_a_loop_put_back_runs_every_round() -> void:
	runner.start("", {"list": [1, 2, 3]}, "loop")
	var state: Dictionary = runner.flow_state()
	runner.set_flow_state({})
	runner.set_flow_state(state)
	for i: int in range(3):
		host.fired.emit()
	assert_eq(host.pings, 3)
	assert_false(runner.running)

func test_the_state_handed_out_is_not_changed_by_what_runs_after() -> void:
	runner.start("", {"list": [1, 2, 3]}, "loop")
	var state: Dictionary = runner.flow_state()
	host.fired.emit()
	host.fired.emit()
	host.fired.emit()
	assert_false(runner.running)
	runner.start("", {"list": [1, 2, 3]}, "loop")
	runner.set_flow_state(state)
	for i: int in range(3):
		host.fired.emit()
	assert_eq(host.pings, 6, "the state taken in the first round is still a first round")
