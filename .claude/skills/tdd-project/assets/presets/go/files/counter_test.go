package {{SLUG}}

import "testing"

func TestStartsEmpty(t *testing.T) {
	if got := NewCounter(3).Value(); got != 0 {
		t.Fatalf("Value() = %d, want 0", got)
	}
}

func TestAddStopsAtTheLimit(t *testing.T) {
	c := NewCounter(3)
	if got := c.Add(2); got != 2 {
		t.Fatalf("Add(2) = %d, want 2", got)
	}
	if got := c.Add(5); got != 1 {
		t.Fatalf("Add(5) = %d, want 1", got)
	}
	if !c.Full() {
		t.Fatal("Full() = false, want true")
	}
}

// A slow test: part of the integration stage only (the unit stage passes -short).
func TestManyCounters(t *testing.T) {
	if testing.Short() {
		t.Skip("slow: not in the quick tier")
	}
	for limit := 0; limit < 2000; limit++ {
		c := NewCounter(limit)
		for !c.Full() {
			c.Add(7)
		}
		if c.Value() != limit {
			t.Fatalf("limit %d: Value() = %d", limit, c.Value())
		}
	}
}
