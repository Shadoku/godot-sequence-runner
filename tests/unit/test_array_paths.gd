extends TestCase
## Array indices in property paths: `$list.0`, `$card.tags.1`, and set_prop's
## `prop="list.0"`. Fixture: tests/fixtures/sequences/array_paths.xml.

const DIR: String = "res://fixtures/sequences/"

## The node a runner drives: records the calls its sequences make.
class Recorder extends Node2D:
	var pings: int = 0
	var rolls: Array[int] = []
	var said: Array[String] = []
	var items: Array[int] = [1, 2, 3]

	func ping() -> void:
		pings += 1

	func record(n: int) -> void:
		rolls.append(n)

	func say(text: String) -> void:
		said.append(text)

var host: Recorder

func before_each() -> void:
	host = Recorder.new()
	add_child(host)

## A runner on the host for array_paths.xml, not started.
func _runner() -> sequence_runner:
	return sequence_runner.attach(host, DIR + "array_paths.xml")

## The vars the fixture's sections read.
func _vars() -> Dictionary:
	return {
		"list": [4, 5, 6],
		"card": {"tags": ["fire", "flying"]},
		"grid": [[1, 2], [3, 4]],
		"names": PackedStringArray(["ann", "bob"]),
	}

func test_a_path_reads_an_array_by_index() -> void:
	var runner := _runner()
	runner.start("", _vars())
	assert_eq(host.rolls, [4, 3, 3] as Array[int], "$list.0, $grid.1.0, $target.items.2")
	assert_almost_eq(float(runner.scratch_pad["sum"]), 10.0, 0.0001, "an index inside an expression")
	assert_eq(host.said, ["flying", "bob"] as Array[String], "an array inside a dictionary; a packed array")

func test_set_prop_writes_an_array_element() -> void:
	var vars := _vars()
	_runner().start("", vars, "write")
	assert_eq(vars["list"], [10, 6, 6], "prop=\"0\" on a variable holding an array; a value read by index")
	assert_eq(vars["card"]["tags"], ["fire", "cold"], "an array inside a dictionary")
	assert_almost_eq(float(vars["grid"][1][0]), 6.0, 0.0001, "an array inside an array, by expr")
	assert_eq(host.items, [9, 2, 3] as Array[int], "an object's array property")

func test_an_index_out_of_range_is_an_error_and_the_sequence_goes_on() -> void:
	allow_errors = true
	var vars := _vars()
	var runner := _runner()
	runner.start("", vars, "out_of_range")
	assert_true(runner.scratch_pad.has("read"))
	assert_null(runner.scratch_pad["read"], "an index out of range reads as null")
	assert_eq(vars["list"], [4, 5, 6], "nothing is written out of range")
	assert_null(runner.scratch_pad["word"], "a segment that is not an index is an error, as before")
	assert_eq(host.pings, 1, "the sequence went on")

func test_read_member_and_write_member_take_an_index() -> void:
	var list: Array = ["a", "b"]
	assert_eq(sequence_runner.read_member(list, "1"), [true, "b"])
	assert_eq(sequence_runner.read_member(list, "2"), [false, null], "out of range")
	assert_eq(sequence_runner.read_member(list, "-1"), [false, null], "no negative index")
	assert_eq(sequence_runner.read_member(list, "x"), [false, null])
	assert_eq(sequence_runner.read_member(PackedInt32Array([7, 8]), "0"), [true, 7])
	assert_eq(sequence_runner.write_member(list, "0", "z")[0], true)
	assert_eq(list, ["z", "b"])
	assert_eq(sequence_runner.write_member(list, "2", "q")[0], false, "out of range is not appended")
	assert_eq(list, ["z", "b"])
