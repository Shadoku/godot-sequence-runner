extends TestCase
## Blocks: `<if expr> ... <else/> ... </if>` and `<for_each var in index> ...
## </for_each>`, what the reader makes of them (end markers for these two
## names only), validate()'s block problems, a subclass's own `if` /
## `for_each`, and the XML entities an `expr` may hold. Fixtures:
## tests/fixtures/sequences/blocks*.xml and tests/fixtures/broken_sequences/blocks*.xml.

const DIR: String = "res://fixtures/sequences/"
const BROKEN_DIR: String = "res://fixtures/broken_sequences/"

## The node a runner drives: records the calls its sequences make.
class Recorder extends Node2D:
	signal fired

	var pings: int = 0
	var rolls: Array[int] = []

	func ping() -> void:
		pings += 1

	func record(n: int) -> void:
		rolls.append(n)

	## Removes the first element of `list` (the source array of a loop).
	func drop_first(list: Array) -> void:
		list.pop_front()

## A runner whose own `if` and `for_each` replace the built-in blocks: each
## records that it ran and does nothing else.
class CustomBlocksRunner extends sequence_runner:
	var custom_calls: Array[String] = []

	func register_commands() -> void:
		super.register_commands()
		register_command("if", factory_custom_if, PackedStringArray(["expr"]))
		register_command("for_each", factory_custom_for_each, PackedStringArray(["var", "in"]))

	func factory_custom_if(args: Dictionary, _index: int) -> Callable:
		var expr: String = args.get("expr", "")
		return func() -> Variant:
			custom_calls.append("if " + expr)
			return null

	func factory_custom_for_each(args: Dictionary, _index: int) -> Callable:
		var source: String = args.get("in", "")
		return func() -> Variant:
			custom_calls.append("for_each " + source)
			return null

var host: Recorder

func before_each() -> void:
	host = Recorder.new()
	add_child(host)

## Runs `section` of `file` with `vars`. Returns the numbers recorded.
func _rolls(section: String, vars: Dictionary = {}, file: String = "blocks.xml") -> Array[int]:
	host.rolls.clear()
	sequence_runner.attach(host, DIR + file).start("", vars, section)
	return host.rolls.duplicate()

func test_if_runs_its_first_part_when_the_expr_holds_else_the_second() -> void:
	assert_eq(_rolls("if_else", {"n": 3}), [1, 3] as Array[int], "3 > 2: the first part")
	assert_eq(_rolls("if_else", {"n": 2}), [2, 3] as Array[int], "2 > 2 fails: the <else/> part")
	assert_eq(_rolls("if_only", {"flag": true}), [1, 3] as Array[int])
	assert_eq(_rolls("if_only", {"flag": false}), [3] as Array[int], "no <else/>: nothing")

func test_for_each_sets_the_var_and_the_index_per_round() -> void:
	var runner := sequence_runner.attach(host, DIR + "blocks.xml")
	runner.start("", {"list": [5, 6, 7]}, "loop")
	assert_eq(host.rolls, [5, 0, 6, 1, 7, 2, 9] as Array[int])
	assert_eq(runner.scratch_pad["m"], 7, "the var keeps the last element")
	assert_eq(typeof(runner.scratch_pad["i"]), TYPE_INT, "the index is an int")

func test_blocks_nest() -> void:
	assert_eq(_rolls("nested_loops", {"rows": [[1, 2], [], [3]]}), [1, 2, 0, 0, 3, 0] as Array[int], "a loop in a loop, an empty inner one")
	assert_eq(_rolls("if_in_loop", {"list": [1, 2, 3]}), [0, 2, 3] as Array[int], "an if in a loop")
	assert_eq(_rolls("loop_in_if", {"go": true, "list": [4, 5]}), [4, 5, 9] as Array[int], "a loop in an if")
	assert_eq(_rolls("loop_in_if", {"go": false, "list": [4, 5]}), [-1, 9] as Array[int], "a loop in an if's first part, skipped")

func test_an_empty_array_skips_the_body() -> void:
	assert_eq(_rolls("loop", {"list": []}), [9] as Array[int])
	assert_eq(_rolls("loop", {"list": PackedInt32Array([4])}), [4, 0, 9] as Array[int], "a packed array is iterated too")

func test_something_that_is_not_an_array_is_an_error_and_skips_the_body() -> void:
	allow_errors = true
	assert_eq(_rolls("loop", {"list": 5}), [9] as Array[int], "an int")
	assert_eq(_rolls("loop", {}), [9] as Array[int], "an unresolvable reference")

func test_for_each_iterates_a_snapshot() -> void:
	var list: Array = [1, 2, 3]
	assert_eq(_rolls("mutate", {"list": list}), [1, 2, 3] as Array[int], "removing from the source does not shift the loop")
	assert_eq(list, [], "the body did remove from the source")

func test_goto_out_of_a_loop_abandons_it() -> void:
	assert_eq(_rolls("goto_out", {"list": [1, 2, 3]}), [1, 2, 1, 2, 9] as Array[int], "entering again from above starts afresh")
	assert_eq(_rolls("goto_in", {"list": [1, 2, 3]}), [1, 1, 9] as Array[int], "jumping back into the abandoned body does not resume it")

func test_labels_inside_blocks() -> void:
	assert_eq(_rolls("label_in_if"), [2, 1] as Array[int], "a goto into an if's first part")
	assert_eq(_rolls("next_round", {"list": [1, 2, 3]}), [1, 3] as Array[int], "a goto to a label before </for_each> goes to the next round")

func test_self_closed_and_empty_blocks_do_nothing() -> void:
	assert_eq(_rolls("empty_blocks", {"list": [1]}), [9] as Array[int])

func test_start_clears_the_loop_state() -> void:
	var runner := sequence_runner.attach(host, DIR + "blocks.xml")
	runner.start("", {"list": [1, 2, 3], "skip": 0}, "resume")
	assert_eq(host.pings, 1)
	runner.start("", {"list": [1, 2, 3], "skip": 1}, "resume")
	host.fired.emit()
	assert_eq(host.pings, 2, "the new run jumped into the body")
	assert_true(runner.running)
	host.fired.emit()
	assert_eq(host.pings, 2, "the loop of the run before start() is gone: no next round")
	assert_false(runner.running)

func test_entities_in_an_expr_are_decoded() -> void:
	var runner := sequence_runner.attach(host, DIR + "blocks_entities.xml")
	runner.start("", {"n": 2})
	assert_eq(host.rolls, [1] as Array[int], "&lt; reads as <")
	assert_eq(runner.scratch_pad["between"], true, "&gt; and &amp;&amp; read as > and &&")
	host.rolls.clear()
	runner.start("", {"n": 5})
	assert_eq(host.rolls, [2] as Array[int])
	assert_eq(runner.scratch_pad["between"], false)
	var args: Dictionary = sequence_runner.read_sections(DIR + "blocks_entities.xml")[""][0]["args"]
	assert_eq(args["expr"], "$n < 3", "the reader hands the decoded text on")

func test_the_reader_adds_end_markers_for_if_and_for_each_only() -> void:
	var path := BROKEN_DIR + "blocks_reader.xml"
	var expected: Array[Dictionary] = [
		{"name": "wait", "args": {"seconds": "0"}},
		{"name": "call", "args": {"method": "ping"}},
		{"name": "note", "args": {"text": "x"}},
		{"name": "if", "args": {"expr": "1"}},
		{"name": "end_if", "args": {}},
		{"name": "for_each", "args": {"var": "m", "in": "$list"}},
		{"name": "end_for_each", "args": {}},
		{"name": "if", "args": {"expr": "0"}},
		{"name": "else", "args": {}},
		{"name": "end_if", "args": {}},
	]
	assert_eq(sequence_runner.read_sections(path, true)[""], expected)
	var runner := sequence_runner.new()
	assert_eq(runner.validate(path), PackedStringArray([path + ":: unknown command <note>"]), "a nested unknown element is a command, as before")
	runner.free()

func test_validate_lists_block_problems() -> void:
	var runner := sequence_runner.new()
	var path := BROKEN_DIR + "blocks.xml"
	var problems := runner.validate(path)
	assert_eq(problems.size(), 7, str(problems))
	if problems.size() == 7:
		assert_eq(problems[0], path + ":: <else/> outside an <if>")
		assert_true(problems[1].begins_with(path + ":: <if> expr \"1 +\": "), problems[1])
		assert_eq(problems[2], path + ":: <for_each> has no attribute \"of\"")
		assert_eq(problems[3], path + ":: <for_each> needs in")
		assert_eq(problems[4], path + ":: <else/> outside an <if>", "directly inside a for_each")
		assert_eq(problems[5], path + ":: a second <else/> in one <if>")
		assert_eq(problems[6], path + ":: <if> needs expr")
	runner.free()

func test_a_broken_block_is_an_error_when_started_and_the_rest_runs() -> void:
	allow_errors = true
	var runner := sequence_runner.attach(host, "")
	runner.start(BROKEN_DIR + "blocks.xml", {"list": [1]})
	assert_eq(runner.compile_errors, 7)
	assert_eq(host.pings, 1, "an if whose expr does not parse, or that has none, skips its first part; the last ping runs")

func test_a_subclass_if_and_for_each_win_and_the_markers_do_nothing() -> void:
	var runner := CustomBlocksRunner.new()
	runner.xml_path = DIR + "blocks_custom.xml"
	host.add_child(runner)
	assert_eq(runner.validate(DIR + "blocks_custom.xml"), PackedStringArray())
	runner.start("", {"list": [1, 2]})
	assert_eq(runner.compile_errors, 0)
	assert_eq(runner.custom_calls, ["if false", "for_each $list"] as Array[String])
	assert_eq(host.rolls, [1, 2, 3] as Array[int], "the bodies run once, as plain commands")
