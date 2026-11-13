- Tests: `*_test.go` next to the code, functions `TestXxx(t *testing.T)`.
- Tiers by `testing.Short()`: a test that is slow or crosses a boundary (process,
  network, disk beyond `t.TempDir()`, a service) starts with
  `if testing.Short() { t.Skip("slow") }`. The quick tier runs `go test -short`.
- One test: `python3 tools/check.py --filter TestAddStops` (go's `-run` regex).
- Time: take the clock as a parameter (`now func() time.Time`), or use `testing/synctest`
  where the Go version has it. Never `time.Sleep` in a test.
- Randomness: take a `*rand.Rand` seeded in the test.
- go caches passing packages itself; the pass cache of tools/check.py sits on top of it.
