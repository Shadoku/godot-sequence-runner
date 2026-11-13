// Package {{SLUG}} holds a worked example of logic that is easy to test: plain state,
// no I/O, no clock.
package {{SLUG}}

// Counter counts up to a limit.
type Counter struct {
	limit int
	value int
}

// NewCounter returns an empty counter. A negative limit counts as zero.
func NewCounter(limit int) *Counter {
	return &Counter{limit: max(0, limit)}
}

// Add adds amount, stopping at the limit, and returns how much was added.
func (c *Counter) Add(amount int) int {
	added := max(0, min(amount, c.limit-c.value))
	c.value += added
	return added
}

// Value is the count so far.
func (c *Counter) Value() int { return c.value }

// Full reports whether the limit is reached.
func (c *Counter) Full() bool { return c.value >= c.limit }
