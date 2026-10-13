const assert = require("node:assert/strict"),
  E = require("../web/engine.js"),
  D = require(process.env.PARTITION_GRAPH || "../data/graph.json");
const groups = D.files.map((f, i) => ({
  members: D.functions.flatMap((v, j) => (v.f === i ? [j] : [])),
}));
assert.equal(E.metrics(D, groups).cut, D.stats.crossCalls);
// API -> implementation; two consumers -> API. Their weight must not override a keep-together decision.
const fixture = {
  functions: [{ s: 0 }, { s: 1 }, { s: 0 }, { s: 0 }],
  edges: [
    [0, 1, 1],
    [2, 0, 1],
    [3, 0, 1],
  ],
};
assert.equal(
  E.metrics(fixture, [{ members: [0, 1] }, { members: [2, 3] }]).cut,
  2,
);
assert.equal(
  E.metrics(fixture, [{ members: [0, 2, 3] }, { members: [1] }]).cut,
  1,
);
console.log(
  "PASS: original cut and API/helper counterexample.",
);
