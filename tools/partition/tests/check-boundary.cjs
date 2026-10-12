const assert = require("node:assert/strict"),
  B = require("../web/boundary.js"),
  D = require(process.env.PARTITION_GRAPH || "../data/graph.json");
const fixture = {
  edges: [
    [0, 1, 2],
    [1, 0, 3],
    [1, 2, 4],
    [2, 1, 5],
    [1, 1, 7],
    [0, 2, 9],
  ],
};
const groups = [
  { id: "outside-a", name: "A", members: [0] },
  { id: "inside", name: "I", members: [1] },
  { id: "outside-b", name: "B", members: [2] },
];
const b = B.collect(fixture, new Set([1]), groups);
assert.equal(b.incoming, 7);
assert.equal(b.outgoing, 7);
assert.equal(b.ports.length, 4);
assert.deepEqual(b.functions.get(1), { in: 7, out: 7 });
assert.equal(
  b.links.reduce((s, l) => s + l.calls, 0),
  14,
);
assert.equal(B.collect(fixture, new Set([0, 1, 2]), groups).ports.length, 0);
assert.equal(B.collect(fixture, new Set(), groups).ports.length, 0);
const merged = B.collect(fixture, new Set([1]), [
  groups[1],
  { id: "combined", name: "Combined", members: [0, 2] },
]);
assert.equal(merged.ports.length, 2);
assert.equal(merged.incoming, b.incoming);
assert.equal(merged.outgoing, b.outgoing);
const ids = new Set(
  D.functions.flatMap((f, i) =>
    D.files[f.f].id === "src/macros.x" ? [i] : [],
  ),
);
const files = D.files.map((f, i) => ({
  id: String(i),
  name: f.id,
  members: D.functions.flatMap((fn, j) => (fn.f === i ? [j] : [])),
}));
const actual = B.collect(D, ids, files);
const crossing = D.edges.filter(([a, b]) => ids.has(a) !== ids.has(b));
assert.equal(
  actual.incoming,
  crossing.filter((e) => ids.has(e[1])).reduce((n, e) => n + e[2], 0),
);
assert.equal(
  actual.outgoing,
  crossing.filter((e) => ids.has(e[0])).reduce((n, e) => n + e[2], 0),
);
assert.equal(
  actual.ports.reduce((n, p) => n + p.edges.length, 0),
  crossing.length,
);
console.log(
  "PASS: boundary direction, aggregation, and complete current-snapshot coverage",
);
