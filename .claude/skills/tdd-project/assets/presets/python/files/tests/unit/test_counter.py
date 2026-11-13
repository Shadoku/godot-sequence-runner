import unittest

from counter import Counter


class CounterTest(unittest.TestCase):
    def test_starts_empty(self) -> None:
        self.assertEqual(Counter(3).value, 0)

    def test_add_stops_at_the_limit(self) -> None:
        counter = Counter(3)
        self.assertEqual(counter.add(2), 2)
        self.assertEqual(counter.add(5), 1)
        self.assertTrue(counter.full)

    def test_negative_limit_is_refused(self) -> None:
        with self.assertRaises(ValueError):
            Counter(-1)


if __name__ == "__main__":
    unittest.main()
