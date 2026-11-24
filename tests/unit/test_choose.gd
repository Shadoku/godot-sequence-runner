extends TestCase
## <choose> jumps to one of its <option goto weight> children at random, by
## weight, on the runner's rng. Fixture: choose.xml.

const FILE: String = "res://fixtures/sequences/choose.xml"
const BROKEN: String = "res://fixtures/broken_sequences/choose.xml"

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
	runner.rng = RandomNumberGenerator.new()
	runner.rng.seed = 7

## What `rounds` runs of `weighted` pick, in order, as one string.
func _picks(rounds: int) -> String:
	var picks := ""
	for i: int in range(rounds):
		runner.start("", {}, "weighted")
		picks += str(runner.scratch_pad["picked"])
	return picks

func test_choose_picks_by_weight() -> void:
	var picks := _picks(400)
	var a := picks.count("a")
	assert_eq(a + picks.count("b"), 400)
	assert_gt(a, 260, "weight 3 against the default 1: about 300 of 400")
	assert_lt(a, 340)

func test_a_seeded_rng_repeats_the_picks() -> void:
	var first := _picks(20)
	runner.rng.seed = 7
	assert_eq(_picks(20), first)

func test_an_option_of_weight_zero_is_never_picked_and_a_weight_is_a_token() -> void:
	for i: int in range(50):
		runner.start("", {"w": 0.5}, "zero_weight")
		assert_eq(runner.scratch_pad["picked"], "always")

func test_no_weight_above_zero_is_a_run_time_error_and_nothing_jumps() -> void:
	allow_errors = true
	runner.start("", {}, "no_weight")
	assert_eq(host.pings, 1)
	runner.stop_on_error = true
	runner.start("", {}, "no_weight")
	assert_true(runner.failed)
	assert_eq(host.pings, 1)

func test_the_options_are_not_commands_of_the_section() -> void:
	var commands: Array = sequence_runner.read_sections(FILE)["after"]
	var names: Array = commands.map(func(cmd: Dictionary) -> String: return cmd["name"])
	assert_eq(names, ["choose", "label", "call"])
	runner.start("", {}, "after")
	assert_eq(host.pings, 1)

func test_compile_errors() -> void:
	var problems := "\n".join(runner.validate(BROKEN))
	assert_eq(runner.compile_errors, 4, problems)
	assert_true(problems.contains(":empty: <choose> needs at least one <option>"), problems)
	assert_true(problems.contains(":missing_label: <choose>: an <option> goes to a label the section lacks: \"nowhere\""), problems)
	assert_true(problems.contains(":attribute: <option> has no attribute \"chance\""), problems)
	assert_true(problems.contains("choose.xml: <wait> inside a <choose> (ignored): only <option> belongs there"), problems)
