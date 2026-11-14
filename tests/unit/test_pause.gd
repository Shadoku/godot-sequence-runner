extends TestCase
## <pause />: without `time` it pauses the scene tree until an <unpause /> and
## reports no error. With a `time` above 0 the tree is unpaused after it. A
## `time` of 0 or less pauses too and is a run-time error.
## Fixture: pause.xml.

const FILE: String = "res://fixtures/sequences/pause.xml"

## The node a runner drives: counts its pings.
class Pinged extends Node2D:
	var pings: int = 0

	func ping() -> void:
		pings += 1

var host: Pinged

func before_each() -> void:
	host = Pinged.new()
	add_child(host)

func after_each() -> void:
	get_tree().paused = false

## A runner on the host for pause.xml, `stop_on_error` as given.
func _runner(stop_on_error: bool) -> sequence_runner:
	var runner := sequence_runner.attach(host, FILE)
	runner.stop_on_error = stop_on_error
	return runner

# No test of a bare <pause /> sets allow_errors: a printed error fails it.
func test_a_bare_pause_pauses_the_tree_without_an_error() -> void:
	var runner := _runner(false)
	runner.start("", {}, "bare")
	assert_true(get_tree().paused, "the tree is paused")
	assert_eq(host.pings, 1, "the sequence went on")
	assert_false(runner.running, "and ran to its end")

func test_a_bare_pause_does_not_fail_with_stop_on_error() -> void:
	var runner := _runner(true)
	runner.start("", {}, "bare")
	assert_true(get_tree().paused, "the tree is paused")
	assert_false(runner.failed, "not failed")
	assert_false(runner.stopped, "not stopped")
	assert_eq(host.pings, 1, "the sequence ran to its end")

func test_unpause_ends_a_bare_pause() -> void:
	var runner := _runner(true)
	runner.start("", {}, "unpaused")
	assert_false(get_tree().paused, "the tree is unpaused")
	assert_false(runner.failed)
	assert_eq(host.pings, 1)

func test_a_time_of_zero_pauses_and_is_an_error() -> void:
	allow_errors = true
	var runner := _runner(true)
	runner.start("", {}, "zero")
	assert_true(get_tree().paused, "the tree is paused")
	assert_true(runner.failed, "the error was reported")
	assert_eq(host.pings, 0, "stop_on_error stopped the sequence")

func test_a_negative_time_pauses_and_is_an_error() -> void:
	allow_errors = true
	var runner := _runner(true)
	runner.start("", {}, "negative")
	assert_true(get_tree().paused, "the tree is paused")
	assert_true(runner.failed, "the error was reported")
	assert_eq(host.pings, 0)

func test_a_time_of_zero_goes_on_without_stop_on_error() -> void:
	allow_errors = true
	var runner := _runner(false)
	runner.start("", {}, "zero")
	assert_true(get_tree().paused)
	assert_false(runner.failed)
	assert_eq(host.pings, 1, "the sequence went on")

func test_a_timed_pause_unpauses_after_its_time() -> void:
	var runner := _runner(true)
	runner.start("", {}, "timed")
	assert_true(get_tree().paused, "paused while the time runs")
	assert_eq(host.pings, 0, "the sequence waits")
	assert_true(await await_signal(runner.sequence_finished, 2.0), "the sequence ends")
	assert_false(get_tree().paused, "unpaused after the time")
	assert_false(runner.failed)
	assert_eq(host.pings, 1)
