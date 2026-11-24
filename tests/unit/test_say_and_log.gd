extends TestCase
## <say speaker text> and <log text> hand text to the runner's `presenter`,
## with {expression} placeholders filled in. Fixture: say.xml.

const FILE: String = "res://fixtures/sequences/say.xml"
const BROKEN: String = "res://fixtures/broken_sequences/say.xml"

class Recorder extends Node2D:
	var pings: int = 0

	func ping() -> void:
		pings += 1

## A presenter whose say() waits for `continued`.
class FakePresenter extends RefCounted:
	signal continued

	var said: Array = []
	var logged: Array = []

	func say(speaker: String, text: String) -> Signal:
		said.append([speaker, text])
		return continued

	func log(text: String) -> void:
		logged.append(text)

## A presenter whose say() shows the line and returns nothing.
class InstantPresenter extends RefCounted:
	var said: Array = []

	func say(speaker: String, text: String) -> void:
		said.append([speaker, text])

var host: Recorder
var runner: sequence_runner
var presenter: FakePresenter
const VARS: Dictionary = {"who": "Tutor", "apples": 3, "name": "Ann"}

func before_each() -> void:
	host = Recorder.new()
	add_child(host)
	runner = sequence_runner.attach(host, FILE)
	presenter = FakePresenter.new()
	runner.presenter = presenter

func test_say_shows_the_line_and_waits_for_the_presenter() -> void:
	runner.start("", VARS, "say")
	assert_eq(presenter.said, [["Tutor", "You have 3 apples, Ann."]])
	assert_true(runner.running)
	assert_eq(host.pings, 0)
	presenter.continued.emit()
	assert_false(runner.running)
	assert_eq(host.pings, 1)

func test_say_goes_on_at_once_when_the_presenter_returns_nothing() -> void:
	var instant := InstantPresenter.new()
	runner.presenter = instant
	runner.start("", {}, "plain")
	assert_eq(instant.said, [["", "No speaker, no placeholder."]])
	assert_eq(host.pings, 1)

func test_say_without_a_presenter_goes_on() -> void:
	runner.presenter = null
	runner.start("", VARS, "say")
	assert_eq(host.pings, 1)

func test_log_fills_in_expressions() -> void:
	runner.start("", VARS, "log")
	assert_eq(presenter.logged, ["4 is one more; half is 1.5; ab"])

func test_log_without_a_presenter_goes_on() -> void:
	runner.presenter = null
	runner.start("", VARS, "log")
	assert_false(runner.running)

func test_a_run_child_has_the_presenter() -> void:
	runner.start("", VARS, "runs")
	assert_eq(presenter.logged.size(), 1)

func test_a_placeholder_that_cannot_be_resolved_is_a_run_time_error() -> void:
	allow_errors = true
	runner.start("", {}, "unresolved")
	assert_eq(host.pings, 1)
	runner.stop_on_error = true
	runner.start("", {}, "unresolved")
	assert_true(runner.failed)
	assert_eq(presenter.logged.size(), 1, "the failed log shows nothing")

func test_a_malformed_placeholder_is_a_compile_error() -> void:
	var problems := runner.validate(BROKEN)
	assert_eq(problems.size(), 1)
	assert_true(problems[0].contains("<say> text \"You have {1 +} apples\": {1 +}:"), problems[0])

func test_display_text() -> void:
	assert_eq(sequence_runner.display_text(4.0), "4")
	assert_eq(sequence_runner.display_text(1.5), "1.5")
	assert_eq(sequence_runner.display_text("x"), "x")
	assert_eq(sequence_runner.display_text(true), "true")
