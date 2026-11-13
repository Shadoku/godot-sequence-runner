- Unit tests: `tests/unit/test_*.py`, `unittest.TestCase` classes, methods named `test_*`.
  They import the code under `src/` directly (`PYTHONPATH=src`, set in check.toml) and
  touch no file, network, subprocess or clock.
- Integration tests: `tests/integration/test_*.py`. Anything that starts a process,
  opens a socket, writes outside a temp directory or needs a service goes here.
- One test: `python3 tools/check.py --filter test_add_stops_at_the_limit` (unittest's
  `-k`: a substring of the test's name or class).
- Time: take the clock as a parameter (`now: Callable[[], float] = time.monotonic`) and
  pass a fake one in tests, or use `unittest.mock.patch("time.sleep")`. Never `sleep`
  to wait for something: poll a condition with a short deadline, or better, call the
  thing directly.
- Randomness: take a `random.Random(seed)` as a parameter; do not use the module's
  global functions in code under test.
