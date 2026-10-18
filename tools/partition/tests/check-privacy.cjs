const assert = require("node:assert/strict");
const { createHash } = require("node:crypto");
const E = require("../web/engine.js");
const d = {
  functions: [
    { f: 0 },
    { f: 0 },
    { f: 0, s: 1 },
    { f: 0, s: 1 },
    { f: 0 },
    { f: 1, s: 1 },
    { f: 0, k: 1 },
  ],
  edges: [
    [0, 2, 1],
    [1, 2, 2],
    [2, 3, 1],
    [3, 2, 1],
    [1, 4, 9],
    [0, 5, 1],
    [6, 3, 1],
  ],
};
const ties = E.privacyTies(d),
  all = d.functions.map((_, v) => v),
  blocks = E.atoms(all, ties);
assert(blocks.some((c) => [0, 1, 2, 3, 6].every((v) => c.includes(v))));
assert(blocks.some((c) => c.length === 1 && c[0] === 4));
assert(blocks.some((c) => c.length === 1 && c[0] === 5));
const m = E.decomposition(d, blocks);
assert.equal(m.privateTargets, 1);
assert.equal(m.publicEdges[0][2], 9);
assert.equal(m.topEdges.length, 1);
assert.equal(m.authored, 6);
assert.deepEqual(m.topLevel, [6]);
const tiers = {
  functions: [
    { f: 0, p: "a" },
    { f: 0, p: "a", s: 1, v: "static" },
    { f: 0, p: "b", s: 1, v: "module" },
  ],
  edges: [
    [0, 1, 1],
    [0, 2, 1],
  ],
};
const split = E.metrics(tiers, [{ members: [0] }, { members: [1, 2] }]);
assert.deepEqual(split.exposed.sort(), [1, 2]);
assert.deepEqual(split.toModule, [1]);
console.log('PASS: shared and transitive static components, public boundaries, tiered promotions, and top-level coverage');
