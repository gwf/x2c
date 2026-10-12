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
const proposals = E.suggestMoves(data, groups, [], new Set([0, 1, 2]));
assert(
  proposals.some(
    (p) =>
      p.members.length === 1 &&
      p.members[0] === 0 &&
      p.delta === -9 &&
      p.added.includes(1),
  ),
);
assert(
  proposals.some(
    (p) => p.members.includes(0) && p.members.includes(1) && p.delta === -10,
  ),
);
for (const p of proposals) {
  const moved = new Set(p.members);
  const afterGroups = groups.map((g) => ({
    ...g,
    members: g.members
      .filter((v) => !moved.has(v))
      .concat(g.id === p.to ? p.members : []),
  }));
  const after = E.metrics(data, afterGroups);
  assert.equal(after.cut - before.cut, p.delta);
  assert.deepEqual(
    p.added,
    after.exposed.filter((v) => !before.exposed.includes(v)),
  );
  assert.deepEqual(
    p.removed,
    before.exposed.filter((v) => !after.exposed.includes(v)),
  );
  assert(afterGroups.every((g) => g.members.length));
}
const tied = E.suggestMoves(data, groups, [[0, 1]], new Set([0, 1, 2]));
assert(tied.length);
assert(tied.every((p) => p.members.includes(0) === p.members.includes(1)));
const initializer = {
  ...data,
  functions: [{ k: true }, ...data.functions.slice(1)],
};
assert(E.suggestMoves(initializer, groups, [], new Set([0])).length === 0);
assert.deepEqual(groups[0].members, [0, 1, 2]);
assert.deepEqual(
  proposals,
  E.suggestMoves(data, groups, [], new Set([0, 1, 2])),
);
console.log(
  "PASS: local moves and neighbor bundles, exact cut/private deltas, ties, initializers, nonempty groups, no mutation",
);

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
assert(
  E.suggestMoves(visibility, groups, [], new Set([0]), "localize").some(
    (p) => p.members.length === 1 && p.delta === 0 && p.localized.includes(0),
  ),
);
assert(
  !E.suggestMoves(visibility, groups, [], new Set([0])).some(
    (p) => p.members.length === 1 && p.delta === 0,
  ),
);
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
const focus = new Set(corpus.find((g) => g.id === "src/compiler.x").members);
const candidates = E.suggestMoves(D, corpus, [], focus, "localize");
assert(candidates.length);
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
