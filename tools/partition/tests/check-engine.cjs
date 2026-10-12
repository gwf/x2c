const assert = require("node:assert/strict"),
  E = require("../web/engine.js"),
  D = require(process.env.PARTITION_GRAPH || "../data/graph.json");
const groups = D.files.map((f, i) => ({
  members: D.functions.flatMap((v, j) => (v.f === i ? [j] : [])),
}));
assert.equal(E.metrics(D, groups).cut, D.stats.crossCalls);
for (const name of ["src/compiler.x", "src/parse.x", "lib/typed-array.x"]) {
  const i = D.files.findIndex((f) => f.id === name),
    members = groups[i].members;
  for (const k of [1, 2, 4, 8, 40])
    for (const t of [0, 0.38, 1]) {
      const ties = [members.slice(0, 3)],
        parts = E.partition(D, members, k, t, ties);
      assert.equal(parts.length, k);
      assert.deepEqual(
        parts.flat().sort((a, b) => a - b),
        members.slice().sort((a, b) => a - b),
      );
      assert(parts.some((p) => ties[0].every((v) => p.includes(v))));
    }
}
// API -> implementation; two consumers -> API. Their weight must not override a keep-together decision.
const fixture = {
  functions: [{ s: 0 }, { s: 1 }, { s: 0 }, { s: 0 }],
  edges: [
    [0, 1, 1],
    [2, 0, 1],
    [3, 0, 1],
  ],
};
for (const t of [0, 0.5, 1]) {
  const p = E.partition(fixture, [0, 1, 2, 3], 2, t, [[0, 1]]);
  assert(p.some((g) => g.includes(0) && g.includes(1)));
}
assert.equal(
  E.metrics(fixture, [{ members: [0, 1] }, { members: [2, 3] }]).cut,
  2,
);
assert.equal(
  E.metrics(fixture, [{ members: [0, 2, 3] }, { members: [1] }]).cut,
  1,
);
console.log(
  "PASS: original cut, exact counts, complete membership, constraints, and API/helper counterexample.",
);
