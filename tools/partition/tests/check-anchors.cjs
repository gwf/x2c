const assert = require("node:assert/strict");
const { anchors } = require("../web/engine.js");
const data = {
  functions: [
    { f: 0 },
    { f: 0, s: true },
    { f: 0, s: true },
    { f: 0 },
    { f: 0, s: true },
    { f: 1 },
    { f: 1, s: true },
  ],
  edges: [
    [5, 0, 9],
    [5, 0, 1],
    [0, 1, 1],
    [1, 2, 1],
    [2, 1, 1],
    [2, 0, 1],
    [0, 3, 1],
    [3, 4, 1],
    [0, 6, 1],
    [3, 2, 1],
  ],
};
const rows = anchors(data);
assert.deepEqual([...rows[0].dependencies], [1, 2]);
assert.deepEqual(rows[0].callers, [5]);
assert.deepEqual(rows[0].shared, [2]);
assert.equal(rows[0].raw, Math.log1p(1) * Math.log1p(2));
assert.equal(rows[0].score, 100);
assert.deepEqual([...rows[1].dependencies], [2]);
assert.equal(rows[3].score, 0);
assert.equal(anchors({ functions: [{ f: 0 }], edges: [] })[0].score, 0);
console.log(
  "Anchor checks passed: directed closure, cycles, distinct callers, shared helpers, normalization.",
);
