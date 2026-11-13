//! A worked example of logic that is easy to test: plain state, no I/O, no clock.

/// Counts up to a limit.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Counter {
    limit: u32,
    value: u32,
}

impl Counter {
    pub fn new(limit: u32) -> Self {
        Self { limit, value: 0 }
    }

    /// Add `amount`, stopping at the limit. Returns how much was added.
    pub fn add(&mut self, amount: u32) -> u32 {
        let added = amount.min(self.limit - self.value);
        self.value += added;
        added
    }

    pub fn value(&self) -> u32 {
        self.value
    }

    pub fn is_full(&self) -> bool {
        self.value >= self.limit
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn starts_empty() {
        assert_eq!(Counter::new(3).value(), 0);
    }

    #[test]
    fn add_stops_at_the_limit() {
        let mut counter = Counter::new(3);
        assert_eq!(counter.add(2), 2);
        assert_eq!(counter.add(5), 1);
        assert!(counter.is_full());
    }
}
