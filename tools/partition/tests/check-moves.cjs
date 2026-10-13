const assert = require("node:assert/strict");
const E = require("../web/engine.js");
const data = {
  functions: [{}, { s: true }, {}, {}, {}, {}],
  edges: [
    [3, 0, 5],
    [4, 0, 5],
    [0, 1, 1],
  ],
};
const groups = [
  { id: "a", members: [0, 1, 2] },
  { id: "b", members: [3, 4, 5] },
];
const before = E.metrics(data, groups);
// Localizing a public helper can exchange one incoming cut for an outgoing cut.
const visibility = {
  functions: [{}, { s: true }, {}, {}, {}, {}],
  edges: [
    [3, 0, 1],
    [0, 1, 1],
  ],
};
const neutral = E.moveEvaluator(visibility, groups).impact([0], "b");
assert.equal(neutral.delta, 0);
assert.equal(neutral.addedCalls, 1);
assert.equal(neutral.removedCalls, 1);
assert.deepEqual(neutral.localized, [0]);
assert.deepEqual(neutral.added, [1]);
assert.deepEqual(neutral.remaining, [{ v: 0, callers: [] }]);
// The written_definitions shape: one caller on either side does not localize it.
const exchanged = {
  ...visibility,
  edges: [
    [2, 0, 1],
    [3, 0, 1],
  ],
};
const unchanged = E.moveEvaluator(exchanged, groups).impact([0], "b");
assert.equal(unchanged.delta, 0);
assert.deepEqual(unchanged.localized, []);
assert.deepEqual(unchanged.remaining, [{ v: 0, callers: [2] }]);
// Full metric recomputation independently verifies effects on the real corpus.
const D = require(process.env.PARTITION_GRAPH || "../data/graph.json");
const corpus = D.files.map((f, i) => ({
  id: f.id,
  members: D.functions.flatMap((v, j) => (v.f === i ? [j] : [])),
}));
const publicLocal = (gs) => {
  const owners = E.membership(gs, D.functions.length);
  const outside = new Set(
    D.edges.filter(([a, b]) => owners[a] !== owners[b]).map(([, b]) => b),
  );
  return new Set(
    D.functions.flatMap((f, i) => (!f.s && !f.k && !outside.has(i) ? [i] : [])),
  );
};
const beforeLocal = publicLocal(corpus);
const evaluator = E.moveEvaluator(D, corpus);
const candidates = D.edges.slice(0,100).filter(([a,b]) => evaluator.owners[a] !== evaluator.owners[b]).map(([a,b]) => ({members:[a],to:corpus[evaluator.owners[b]].id,...evaluator.impact([a],corpus[evaluator.owners[b]].id)}));
for (const p of candidates) {
  const after = corpus.map((g) => ({
    ...g,
    members: g.members
      .filter((v) => !p.members.includes(v))
      .concat(g.id === p.to ? p.members : []),
  }));
  const afterLocal = publicLocal(after);
  assert.equal(E.metrics(D, after).cut, p.afterCut);
  assert.equal(p.afterCut - p.beforeCut, p.delta);
  assert.deepEqual(
    new Set(p.localized),
    new Set([...afterLocal].filter((v) => !beforeLocal.has(v))),
  );
  assert.deepEqual(
    new Set(p.delocalized),
    new Set([...beforeLocal].filter((v) => !afterLocal.has(v))),
  );
}
console.log(
  "PASS: zero-cut visibility gains, remaining outside callers, and independently recomputed corpus effects",
);
