extends TestCase
## <gosub label> jumps to a label and remembers where it came from; <return/>
## goes back to just after it. Fixture: gosub.xml.

const FILE: String = "res://fixtures/sequences/gosub.xml"
const BROKEN: String = "res://fixtures/broken_sequences/gosub.xml"

class Recorder extends Node2D:
	var pings: int = 0

	func ping() -> void:
		pings += 1

var host: Recorder
var runner: sequence_runner

func before_each() -> void:
	host = Recorder.new()
	add_child(host)
	runner = sequence_runner.attach(host, FILE)

func test_gosub_runs_the_subroutine_and_return_goes_back() -> void:
	assert_true(runner.start("", {}, "basic"))
	assert_false(runner.running)
	assert_eq(runner.scratch_pad["trace"], "abc")

func test_gosubs_nest() -> void:
	runner.start("", {}, "nested")
	assert_eq(runner.scratch_pad["trace"], "abcbe")

func test_a_loop_survives_a_gosub_out_of_its_body() -> void:
	runner.start("", {"list": [1, 2, 3]}, "in_loop")
	assert_almost_eq(runner.scratch_pad["sum"], 6.0, 0.001)

func test_a_subroutine_may_wait() -> void:
	runner.start("", {}, "waiting")
	assert_true(runner.running)
	await await_signal(runner.sequence_finished, 1.0)
	assert_eq(host.pings, 2)

func test_return_without_a_gosub_is_a_run_time_error() -> void:
	allow_errors = true
	runner.start("", {}, "bare_return")
	assert_false(runner.failed)
	assert_eq(host.pings, 1, "the sequence goes on")
	runner.stop_on_error = true
	runner.start("", {}, "bare_return")
	assert_true(runner.failed)
	assert_eq(host.pings, 1)

func test_gosub_stops_nesting_at_max_gosub_depth() -> void:
	allow_errors = true
	runner.start("", {}, "too_deep")
	assert_false(runner.running)
	assert_almost_eq(runner.scratch_pad["n"], float(sequence_runner.MAX_GOSUB_DEPTH + 1), 0.001)

func test_start_forgets_the_gosubs_of_the_last_run() -> void:
	allow_errors = true
	runner.start("", {}, "leaves")
	assert_eq(host.pings, 1)
	runner.stop_on_error = true
	runner.start("", {}, "bare_return")
	assert_true(runner.failed, "no gosub is left to return from")

func test_a_gosub_to_a_missing_label_is_a_compile_error() -> void:
	var problems := runner.validate(BROKEN)
	assert_eq(problems.size(), 1)
	assert_true(problems[0].contains("<gosub> to a label the section lacks: \"nowhere\""), problems[0])
