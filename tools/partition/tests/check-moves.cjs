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
