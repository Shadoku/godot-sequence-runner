"""A worked example of logic that is easy to test: plain state, no I/O, no clock."""


class Counter:
    """Counts up to a limit."""

    def __init__(self, limit: int) -> None:
        if limit < 0:
            raise ValueError("limit must not be negative")
        self.limit = limit
        self.value = 0

    def add(self, amount: int = 1) -> int:
        """Add `amount`, stopping at the limit. Returns how much was added."""
        added = max(0, min(amount, self.limit - self.value))
        self.value += added
        return added

    @property
    def full(self) -> bool:
        return self.value >= self.limit
