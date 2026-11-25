extends TestCase
## `source_reader`: when set, the runner asks it for a sequence file's bytes
## instead of opening the path, so files can live in a pack or a virtual file
## system. The "files" here exist only in the reader (FILES); none is on disk.
## The reader is static, so every test unsets it and clears what it cached.

const MAIN: String = "pack://main.xml"
const OTHER: String = "pack://other.xml"
const BROKEN: String = "pack://broken.xml"
const MISSING: String = "pack://missing.xml"
const ON_DISK: String = "res://fixtures/sequences/run_other.xml"

const FILES: Dictionary = {
	MAIN: """<data>
	<sequence name="start">
		<call method="record" arg0="1" />
		<run file="pack://other.xml" section="other" />
		<call method="record" arg0="3" />
	</sequence>
	<sequence name="missing_section">
		<run file="pack://other.xml" section="nowhere" />
	</sequence>
</data>""",
	OTHER: """<data>
	<sequence name="other">
		<call method="record" arg0="2" />
	</sequence>
</data>""",
	BROKEN: """<data>
	<sequence name="a">
		<cal method="record" />
		<goto label="nowhere" />
	</sequence>
	<sequence name="a" />
</data>""",
}

## The node a runner drives: records what its sequences do to it.
class Recorder extends Node2D:
	var rolls: Array = []

	func record(value: Variant) -> void:
		rolls.append(value)

var host: Recorder
## Every path the reader was asked for, in order.
var asked: Array[String] = []

func before_each() -> void:
	host = Recorder.new()
	add_child(host)
	asked = []
	sequence_runner.source_reader = _read

func after_each() -> void:
	sequence_runner.source_reader = Callable()
	for path: String in [MAIN, OTHER, BROKEN, MISSING, ON_DISK]:
		sequence_runner.xml_cache.erase(path)
		sequence_runner.trigger_cache.erase(path)
		sequence_runner.label_cache.erase(path)
		sequence_runner.problem_cache.erase(path)

func _read(path: String) -> PackedByteArray:
	asked.append(path)
	return (FILES.get(path, "") as String).to_utf8_buffer()

func test_a_section_is_read_and_run_from_the_readers_bytes() -> void:
	var runner := sequence_runner.attach(host, OTHER)
	assert_false(FileAccess.file_exists(OTHER), "the file exists only in the reader")
	assert_true(runner.start("", {}, "other"))
	assert_eq(host.rolls, [2])

func test_an_empty_result_is_a_file_that_cannot_be_read() -> void:
	var runner := sequence_runner.new()
	assert_eq(runner.validate(MISSING), PackedStringArray(["%s: cannot be read" % MISSING]))
	host.add_child(runner)
	allow_errors = true
	assert_false(runner.start(MISSING))
	assert_false(sequence_runner.xml_cache.has(MISSING), "nothing cached for it")
	assert_has(asked, MISSING, "the reader was asked, not the disk")

func test_validate_reports_a_broken_file_that_exists_only_in_the_reader() -> void:
	var runner := sequence_runner.new()
	var problems := runner.validate(BROKEN)
	runner.free()
	assert_has(problems, "%s: a second section \"a\" (ignored)" % BROKEN)
	assert_has(problems, "%s:a: unknown command <cal>" % BROKEN)
	assert_eq(problems.size(), 3, "the duplicate, <cal> and the goto: %s" % [problems])

func test_run_reaches_a_second_file_through_the_reader() -> void:
	var runner := sequence_runner.attach(host, MAIN)
	assert_true(runner.start("", {}, "start"))
	assert_eq(host.rolls, [1, 2, 3])

func test_runs_compile_check_finds_a_missing_section_through_the_reader() -> void:
	var runner := sequence_runner.new()
	var problems := runner.validate(MAIN)
	runner.free()
	assert_eq(problems, PackedStringArray([
		"%s:missing_section: <run>: %s has no section \"nowhere\"" % [MAIN, OTHER]]))

func test_sections_and_has_section_work_through_the_reader() -> void:
	assert_eq(sequence_runner.sections(MAIN), PackedStringArray(["start", "missing_section"]))
	assert_true(sequence_runner.has_section(OTHER, "other"))
	assert_false(sequence_runner.has_section(OTHER, "nowhere"))

func test_the_reader_is_asked_once_per_path_with_the_path_given() -> void:
	var runner := sequence_runner.new()
	runner.validate(MAIN)
	runner.validate(MAIN)
	sequence_runner.sections(MAIN)
	sequence_runner.has_section(OTHER, "other")
	host.add_child(runner)
	runner.start(MAIN, {}, "start")
	assert_eq(asked, [MAIN, OTHER] as Array[String])

func test_without_a_reader_a_file_on_disk_is_read_as_before() -> void:
	sequence_runner.source_reader = Callable()
	assert_eq(sequence_runner.sections(ON_DISK), PackedStringArray(["other"]))
	var runner := sequence_runner.attach(host, ON_DISK)
	assert_true(runner.start("", {}, "other"))
	assert_eq(host.rolls, [5])
	assert_eq(asked, [] as Array[String])
