extends TestCase
## A <trigger> with an unknown type: validate() lists it, and start() reports a
## run-time error and runs nothing.

const PATH: String = "res://fixtures/broken_sequences/trigger_type.xml"

## The node a runner drives: counts the pings.
class Recorder extends Node:
	var pings: int = 0

	func ping() -> void:
		pings += 1

var host: Recorder

func before_each() -> void:
	host = Recorder.new()
	add_child(host)

func test_validate_lists_an_unknown_trigger_type() -> void:
	var runner := sequence_runner.new()
	var lines := runner.validate(PATH)
	runner.free()
	assert_eq(lines.size(), 1, str(lines))
	assert_true(lines.size() == 1 and lines[0].contains("singal"), str(lines))

func test_start_reports_an_unknown_trigger_type_and_runs_nothing() -> void:
	allow_errors = true
	var runner := sequence_runner.attach(host, PATH)
	runner.stop_on_error = true
	assert_true(runner.start(), "the section exists, so start() returns true")
	assert_eq(host.pings, 0)
	assert_false(runner.running)
	assert_true(runner.failed, "the unknown type is a run-time error")

func test_the_known_types_validate() -> void:
	var runner := sequence_runner.new()
	for file: String in ["manual_trigger.xml", "signal_trigger.xml"]:
		assert_eq(runner.validate("res://fixtures/sequences/" + file), PackedStringArray())
	runner.free()
