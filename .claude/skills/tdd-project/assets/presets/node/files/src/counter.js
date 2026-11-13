// A worked example of logic that is easy to test: plain state, no I/O, no clock.

/** Counts up to a limit. */
export class Counter {
  constructor(limit) {
    if (limit < 0) throw new RangeError("limit must not be negative");
    this.limit = limit;
    this.value = 0;
  }

  /** Add `amount`, stopping at the limit. Returns how much was added. */
  add(amount = 1) {
    const added = Math.max(0, Math.min(amount, this.limit - this.value));
    this.value += added;
    return added;
  }

  get full() {
    return this.value >= this.limit;
  }
}
