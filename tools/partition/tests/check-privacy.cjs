const assert = require("node:assert/strict");
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
for (const t of [0, 0.3, 1]) {
  const parts = E.partition(d, all, 99, t, ties);
  assert.equal(parts.length, 3);
  const m = E.decomposition(d, parts);
  // Cross-file static call stays visible; privacy rule only binds same-file callers.
  assert.equal(m.privateTargets, 1);
  assert.equal(m.publicEdges[0][2], 9);
  assert.equal(m.topEdges.length, 1);
  assert.equal(m.authored, 6);
  assert.deepEqual(m.topLevel, [6]);
}
const snapshot = require("../data/graph.json");
const ref = require("../web/fixtures/compiler-responsibilities.json");
if (ref.revision.startsWith(snapshot.revision)) {
  const fi = snapshot.files.findIndex((f) => f.id === ref.file);
  const members = snapshot.functions.flatMap((f, v) =>
    f.f === fi && !f.k ? [v] : [],
  );
  assert.equal(members.length, 189);
  const ids = new Map(members.map((v) => [snapshot.functions[v].e, v]));
  const reference = ref.groups.map((g) => g.functions.map((f) => ids.get(f.e)));
  assert(reference.flat().every((v) => v !== undefined));
  assert.equal(new Set(reference.flat()).size, 189);
  const m = E.decomposition(snapshot, reference);
  assert.deepEqual([m.pairs, m.calls, m.privateTargets], [20, 21, 0]);
  for (const [balance, expected] of [
    [0, 18],
    [0.3, 21],
  ])
    assert.equal(
      E.decomposition(snapshot, E.partition(snapshot, members, 8, balance))
        .privateTargets,
      expected,
    );
  const constraints = E.privacyTies(snapshot);
  assert.equal(E.atoms(members, constraints).length, 74);
  const p = E.partition(snapshot, members, 8, 0.3, constraints);
  assert.deepEqual(
    p.map((g) => g.length).sort((a, b) => b - a),
    [56, 27, 21, 17, 17, 17, 17, 17],
  );
  assert.equal(E.decomposition(snapshot, p).calls, 32);
  assert.equal(E.decomposition(snapshot, p).privateTargets, 0);
  console.log(
    "Reproduced compiler reference and constrained partition at " +
      snapshot.revision,
  );
} else
  console.log(
    "Reference comparison skipped: snapshot revision differs (" +
      snapshot.revision +
      ").",
  );
console.log(
  "Privacy fixtures passed: shared helper, transitive dependency, public boundary, top-level, cross-file scope, unattainable count.",
);
