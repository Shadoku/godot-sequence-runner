extends TestCase
## <menu> with <option text goto requires reason> children: the presenter's
## menu() shows the options, and the sequence jumps to the one picked.
## Fixture: menu.xml.

const FILE: String = "res://fixtures/sequences/menu.xml"
const BROKEN: String = "res://fixtures/broken_sequences/menu.xml"

class Recorder extends Node2D:
	var pings: int = 0

	func ping() -> void:
		pings += 1

## A presenter whose menu() waits for `picked`.
class FakePresenter extends RefCounted:
	signal picked(option: int)

	var menus: Array = []

	func menu(options: Array[Dictionary]) -> Signal:
		menus.append(options)
		return picked

## A presenter whose menu() is a coroutine that returns the pick.
class CoroutinePresenter extends RefCounted:
	signal clicked

	func menu(_options: Array[Dictionary]) -> int:
		await clicked
		return 2

## A presenter whose menu() answers at once.
class InstantPresenter extends RefCounted:
	func menu(_options: Array[Dictionary]) -> int:
		return 1

var host: Recorder
var runner: sequence_runner
var presenter: FakePresenter
const RICH: Dictionary = {"item": "lamp", "money": 9, "charm": 2}
const POOR: Dictionary = {"item": "lamp", "money": 1, "charm": 0}

func before_each() -> void:
	host = Recorder.new()
	add_child(host)
	runner = sequence_runner.attach(host, FILE)
	presenter = FakePresenter.new()
	runner.presenter = presenter

func test_menu_shows_the_options_and_jumps_to_the_picked_one() -> void:
	runner.start("", RICH, "shop")
	assert_true(runner.running)
	assert_eq(presenter.menus.size(), 1)
	assert_eq(presenter.menus[0], [
		{"text": "Buy the lamp", "available": true, "reason": ""},
		{"text": "Haggle", "available": true, "reason": ""},
		{"text": "Leave", "available": true, "reason": ""},
	])
	presenter.picked.emit(1)
	assert_false(runner.running)
	assert_eq(runner.scratch_pad["picked"], "haggle")

func test_an_option_whose_requires_fails_is_shown_unavailable_with_its_reason() -> void:
	runner.start("", POOR, "shop")
	var rows: Array = presenter.menus[0]
	assert_eq(rows[0], {"text": "Buy the lamp", "available": false, "reason": "Too expensive"})
	assert_eq(rows[1], {"text": "Haggle", "available": false, "reason": "requires: $charm >= 2"})
	assert_true(rows[2]["available"])
	presenter.picked.emit(2)
	assert_eq(runner.scratch_pad["picked"], "leave")

func test_an_unavailable_answer_is_an_error_and_takes_the_first_available_option() -> void:
	allow_errors = true
	runner.start("", POOR, "shop")
	presenter.picked.emit(0)
	assert_eq(runner.scratch_pad["picked"], "leave")
	runner.start("", RICH, "shop")
	presenter.picked.emit(7)
	assert_eq(runner.scratch_pad["picked"], "buy")

func test_with_stop_on_error_a_bad_answer_fails_the_sequence() -> void:
	allow_errors = true
	runner.stop_on_error = true
	runner.start("", POOR, "shop")
	presenter.picked.emit(0)
	assert_true(runner.failed)
	assert_false(runner.scratch_pad.has("picked"))

func test_without_a_presenter_the_first_available_option_is_taken() -> void:
	runner.presenter = null
	runner.start("", POOR, "shop")
	assert_false(runner.running)
	assert_eq(runner.scratch_pad["picked"], "leave")

func test_a_menu_with_no_available_option_is_an_error_and_is_skipped() -> void:
	allow_errors = true
	runner.start("", POOR, "none_available")
	assert_eq(presenter.menus.size(), 0)
	assert_eq(host.pings, 1)

func test_a_coroutine_presenter_is_waited_for() -> void:
	var coroutine := CoroutinePresenter.new()
	runner.presenter = coroutine
	runner.start("", RICH, "shop")
	assert_true(runner.running)
	coroutine.clicked.emit()
	assert_false(runner.running)
	assert_eq(runner.scratch_pad["picked"], "leave")

func test_a_presenter_may_answer_at_once() -> void:
	runner.presenter = InstantPresenter.new()
	runner.start("", RICH, "shop")
	assert_false(runner.running)
	assert_eq(runner.scratch_pad["picked"], "haggle")

func test_a_pick_after_stop_does_nothing() -> void:
	runner.start("", RICH, "shop")
	runner.stop()
	presenter.picked.emit(1)
	assert_false(runner.running)
	assert_false(runner.scratch_pad.has("picked"))

func test_the_options_are_not_an_attribute_of_the_command() -> void:
	assert_eq(runner.command_attributes["menu"], PackedStringArray())
	assert_eq(runner.validate(FILE), PackedStringArray())

func test_compile_errors() -> void:
	var problems := "\n".join(runner.validate(BROKEN))
	assert_eq(runner.compile_errors, 4, problems)
	assert_true(problems.contains(":empty: <menu> needs at least one <option>"), problems)
	assert_true(problems.contains(":missing_label: <menu>: an <option> goes to a label the section lacks: \"nowhere\""), problems)
	assert_true(problems.contains(":attribute: <option> has no attribute \"weight\""), problems)
	assert_true(problems.contains(":requires: <menu> expr \"$money >=\""), problems)
