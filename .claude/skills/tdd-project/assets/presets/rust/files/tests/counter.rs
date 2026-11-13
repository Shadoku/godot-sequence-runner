//! Integration tier: tests that use the crate from outside, as its users do.
use {{SLUG}}::Counter;

#[test]
fn a_full_counter_takes_nothing_more() {
    let mut counter = Counter::new(2);
    counter.add(5);
    assert_eq!(counter.add(1), 0);
    assert_eq!(counter.value(), 2);
}
