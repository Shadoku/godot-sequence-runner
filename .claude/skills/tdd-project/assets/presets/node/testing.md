- Unit tests: `tests/unit/**/*.test.js`, the built-in `node:test` and `node:assert/strict`.
  They import from `src/` and touch no file, network, subprocess or timer.
- Integration tests: `tests/integration/**/*.test.js`. Anything that starts a process,
  opens a socket, needs a browser or a service goes here.
- One test: `python3 tools/check.py --filter "add stops"` (a pattern on the test's name).
  node exits 0 when the pattern matches nothing (each file still counts as one passing
  test), so check that the count is what you expect.
- Time: `import { mock } from "node:test"`, then `mock.timers.enable()` and
  `mock.timers.tick(ms)`; or pass the clock in (`now = Date.now`). Never wait with
  `setTimeout` in a test.
- Randomness: pass the random source in; do not call `Math.random()` in code under test.
