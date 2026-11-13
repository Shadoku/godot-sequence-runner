"""Integration tier: slower tests that cross a boundary (here: a real subprocess)."""
import subprocess
import sys
import unittest


class CounterScriptTest(unittest.TestCase):
    def test_counter_works_in_a_fresh_interpreter(self) -> None:
        code = "from counter import Counter; c = Counter(2); c.add(5); print(c.value)"
        out = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, check=True)
        self.assertEqual(out.stdout.strip(), "2")


if __name__ == "__main__":
    unittest.main()
