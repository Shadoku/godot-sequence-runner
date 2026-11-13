import assert from "node:assert/strict";
import { test } from "node:test";

import { Counter } from "../../src/counter.js";

test("starts empty", () => {
  assert.equal(new Counter(3).value, 0);
});

test("add stops at the limit", () => {
  const counter = new Counter(3);
  assert.equal(counter.add(2), 2);
  assert.equal(counter.add(5), 1);
  assert.ok(counter.full);
});

test("negative limit is refused", () => {
  assert.throws(() => new Counter(-1), RangeError);
});
