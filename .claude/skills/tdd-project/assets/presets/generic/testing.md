- (Describe here where unit tests live, how they are named, and which runner runs them.)
- (Describe where the slower tests live and what makes a test "slow" in this project.)
- One test: `python3 tools/check.py --filter <name>` once check.toml's stages have a
  `filter` command.
- Time and randomness: pass the clock and the random source into the code under test and
  give tests fake ones; never sleep in a test.
