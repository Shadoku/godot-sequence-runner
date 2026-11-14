extends TestCase
## start_and_wait(): start() then wait for sequence_finished only while the
## sequence still runs, so awaiting it never hangs on a section that finished
## inside start(). Fixtures: start_and_wait.xml, start_and_wait_trigger.xml.

const DIR: String = "res://fixtures/sequences/"

## The node a runner drives: counts its pings.
class Pinged extends Node2D:
	signal fired

	var pings: int = 0

	func ping() -> void:
		pings += 1

var host: Pinged

func before_each() -> void:
	host = Pinged.new()
	add_child(host)

## A runner on the host for the fixture `file`, not started.
func _runner(file: String) -> sequence_runner:
	return sequence_runner.attach(host, DIR + file)

func test_start_and_wait_returns_at_once_for_an_instant_section() -> void:
	var runner := _runner("start_and_wait.xml")
	var finished: Array[int] = [0]
	runner.sequence_finished.connect(func() -> void: finished[0] += 1)
	var ok: bool = await runner.start_and_wait("", {}, "instant")
	assert_true(ok)
	assert_eq(host.pings, 2)
	assert_false(runner.running)
	assert_eq(finished[0], 1, "sequence_finished fired once, inside start()")

func test_start_and_wait_waits_for_an_async_section() -> void:
	var runner := _runner("start_and_wait.xml")
	var ok: bool = await runner.start_and_wait("", {}, "async")
	assert_true(ok)
	assert_eq(host.pings, 1, "it returned after the wait and the ping")
	assert_false(runner.running)

func test_start_and_wait_passes_path_and_vars() -> void:
	var runner := _runner("")
	var ok: bool = await runner.start_and_wait(DIR + "start_and_wait.xml", {"n": 3}, "instant")
	assert_true(ok)
	assert_eq(runner.xml_path, DIR + "start_and_wait.xml")
	assert_eq(runner.scratch_pad.get("n"), 3)

func test_start_and_wait_returns_false_for_a_missing_section() -> void:
	allow_errors = true
	var runner := _runner("start_and_wait.xml")
	var finished: Array[int] = [0]
	runner.sequence_finished.connect(func() -> void: finished[0] += 1)
	var ok: bool = await runner.start_and_wait("", {}, "missing")
	assert_false(ok)
	assert_false(runner.running)
	assert_eq(finished[0], 0)

func test_start_and_wait_does_not_wait_for_a_deferred_trigger() -> void:
	var runner := _runner("start_and_wait_trigger.xml")
	var ok: bool = await runner.start_and_wait()
	assert_true(ok)
	assert_eq(host.pings, 0, "the signal trigger has not fired yet")
	host.fired.emit()
	assert_eq(host.pings, 1)

func test_start_and_wait_returns_when_stopped() -> void:
	var runner := _runner("start_and_wait.xml")
	var done: Array[bool] = [false]
	var waiter := func() -> void:
		await runner.start_and_wait("", {}, "async")
		done[0] = true
	waiter.call()
	assert_true(runner.running)
	assert_false(done[0])
	runner.stop()
	assert_true(done[0], "stop() emits sequence_finished, which ends the wait")
	assert_eq(host.pings, 0)

func test_start_and_wait_follows_a_chain_hand_over() -> void:
	var runner := _runner("start_and_wait.xml")
	var finished: Array[int] = [0]
	runner.sequence_finished.connect(func() -> void: finished[0] += 1)
	var ok: bool = await runner.start_and_wait("", {}, "chain")
	assert_true(ok)
	assert_eq(host.pings, 1, "the chained sequence ran")
	assert_eq(finished[0], 1)

func test_start_and_wait_leaves_start_and_its_hand_over_as_they_were() -> void:
	var runner := _runner("start_and_wait.xml")
	var finished: Array[int] = [0]
	runner.sequence_finished.connect(func() -> void: finished[0] += 1)
	assert_true(runner.start("", {}, "chain"))
	assert_eq(host.pings, 1, "start() chains into ping.xml at once")
	assert_eq(finished[0], 1)
	assert_eq(runner.xml_path, DIR + "ping.xml")
