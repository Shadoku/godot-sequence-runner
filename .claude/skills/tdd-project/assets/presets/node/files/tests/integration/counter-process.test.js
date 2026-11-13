// Integration tier: slower tests that cross a boundary (here: a real subprocess).
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { test } from "node:test";

test("counter works in a fresh process", () => {
  const code =
    'import("./src/counter.js").then(({ Counter }) => { const c = new Counter(2); c.add(5); console.log(c.value); });';
  const out = execFileSync(process.execPath, ["-e", code], { encoding: "utf8" });
  assert.equal(out.trim(), "2");
});
