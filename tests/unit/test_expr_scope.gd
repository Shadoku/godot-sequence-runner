extends TestCase
## What an expression can reach: Godot's built-in functions, random() and
## random_int() on the runner's rng, and nothing of the runner itself. A bare
## name such as `runner` is a run-time error that reads as 0.
## Fixture: expr_scope.xml.

const FILE: String = "res://fixtures/sequences/expr_scope.xml"

## The node a runner drives: counts its pings.
class Pinged extends Node2D:
	var pings: int = 0

	func ping() -> void:
		pings += 1

var host: Pinged

func before_each() -> void:
	host = Pinged.new()
	add_child(host)

func _runner() -> sequence_runner:
	return sequence_runner.attach(host, FILE)

## A generator seeded with `seed_value`.
func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng

## Runs `section` and checks that its expression was an error reading as 0.
func _assert_error_reads_as_zero(section: String) -> void:
	allow_errors = true
	var runner := _runner()
	runner.start("", {}, section)
	var read: Variant = runner.scratch_pad["a"]
	# No assert_eq here: a failure would print the object the expression read.
	assert_true(read is int and read == 0, section + ": reads as 0")
	assert_eq(host.pings, 1, section + ": the sequence went on")
	var strict := _runner()
	strict.stop_on_error = true
	strict.start("", {}, section)
	assert_true(strict.failed, section + ": a run-time error was reported")
	var kept: Variant = strict.scratch_pad["a"]
	assert_true(kept is int and kept == 1, section + ": nothing written after it")

func test_the_bare_name_runner_is_an_error() -> void:
	_assert_error_reads_as_zero("runner")

func test_a_member_of_the_bare_name_runner_is_an_error() -> void:
	_assert_error_reads_as_zero("runner_name")

func test_nothing_the_scope_holds_leads_to_the_runner() -> void:
	allow_errors = true
	var runner := _runner()
	assert_false(is_same(runner.evaluate_expr("self"), runner), "self is not the runner")
	var scope: Object = runner._expr_scope
	assert_not_null(scope, "an expression ran, so the scope exists")
	for property: Dictionary in scope.get_property_list():
		if not property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			continue
		var value: Variant = scope.get(property["name"])
		var reached: Object = null
		if value is Callable:
			reached = (value as Callable).get_object()
		elif value is Object:
			reached = value
		assert_false(reached == runner, "the scope's `%s` reaches the runner" % property["name"])

func test_a_seeded_rng_drives_random_in_an_expression() -> void:
	var runner := _runner()
	runner.rng = _rng(7)
	runner.start("", {}, "roll")
	var twin := _rng(7)
	assert_eq(runner.scratch_pad["whole"], twin.randi_range(1, 1000000))
	assert_almost_eq(float(runner.scratch_pad["part"]), twin.randf_range(0.0, 1.0), 0.0000001)

func test_an_rng_set_after_the_first_expression_is_used() -> void:
	var runner := _runner()
	runner.start("", {}, "roll")
	runner.rng = _rng(11)
	runner.start("", {}, "roll")
	assert_eq(runner.scratch_pad["whole"], _rng(11).randi_range(1, 1000000))

func test_a_runner_that_ran_an_expression_is_freed_with_its_scope() -> void:
	var runner := _runner()
	runner.start("", {}, "roll")
	var scope: WeakRef = weakref(runner._expr_scope)
	assert_not_null(scope.get_ref(), "the scope exists while the runner does")
	runner.free()
	assert_false(is_instance_valid(runner), "the runner is freed")
	assert_null(scope.get_ref(), "and its scope with it")
