- Unit tests: `#[cfg(test)] mod tests` next to the code in `src/` (`cargo test --lib`).
  No file, network, process or clock.
- Integration tests: files under `tests/`, using the crate's public API; anything slow
  or crossing a boundary goes here (`cargo test --tests`).
- One test: `python3 tools/check.py --filter add_stops` (a substring of the test's path).
- Time: take the clock as a parameter (a `Fn() -> Instant`, or a small `Clock` trait with
  a fake for tests); with tokio, `#[tokio::test(start_paused = true)]` and
  `tokio::time::advance`. Never `thread::sleep` in a test.
- Randomness: take an `impl Rng` seeded in the test (`StdRng::seed_from_u64`).
- Commit `Cargo.lock`: it is part of what the check verifies.
