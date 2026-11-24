extends TestCase
## <call_return var ...> is <call> with its `var` required, and <end/> finishes
## the sequence where it stands. Fixtures: call_return.xml, end.xml.

const CALL_RETURN: String = "res://fixtures/sequences/call_return.xml"
const BROKEN: String = "res://fixtures/broken_sequences/call_return.xml"
const END: String = "res://fixtures/sequences/end.xml"

class Recorder extends Node2D:
	var pings: int = 0

	func ping() -> void:
		pings += 1

	func distance() -> int:
		return 40

	func add(a: int, b: int) -> int:
		return a + b

	func later() -> String:
		await get_tree().process_frame
		return "done"

var host: Recorder
var runner: sequence_runner
var finished: Array[int] = [0]

func before_each() -> void:
	host = Recorder.new()
	add_child(host)
	runner = sequence_runner.attach(host, CALL_RETURN)
	finished = [0]
	runner.sequence_finished.connect(func() -> void: finished[0] += 1)

func test_call_return_stores_what_the_method_returns() -> void:
	runner.start("", {}, "stores")
	assert_eq(runner.scratch_pad["dist"], 40)
	assert_eq(runner.scratch_pad["sum"], 42)

func test_call_return_takes_call_s_await() -> void:
	runner.start("", {}, "awaits")
	await await_signal(runner.sequence_finished, 1.0)
	assert_eq(runner.scratch_pad["seen"], "done")

func test_call_return_without_var_is_a_compile_error() -> void:
	var problems := runner.validate(BROKEN)
	assert_eq(problems.size(), 1)
	assert_true(problems[0].contains("<call_return> needs var"), problems[0])

func test_end_finishes_the_sequence_without_stopping_it() -> void:
	runner.start(END, {}, "early")
	assert_eq(host.pings, 1)
	assert_false(runner.running)
	assert_false(runner.stopped, "it ended; it was not stopped")
	assert_false(runner.failed)
	assert_eq(finished[0], 1)

func test_end_ends_from_inside_a_loop_and_a_subroutine() -> void:
	runner.start(END, {"list": [1, 2, 3]}, "in_loop_and_gosub")
	assert_eq(host.pings, 1)
	assert_false(runner.running)
	assert_eq(finished[0], 1)

func test_end_after_a_wait() -> void:
	runner.start(END, {}, "after_wait")
	await await_signal(runner.sequence_finished, 1.0)
	assert_eq(host.pings, 0)
	assert_false(runner.stopped)
