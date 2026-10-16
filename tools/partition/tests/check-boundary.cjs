const assert = require("node:assert/strict"),
  B = require("../web/boundary.js"),
  D = require(process.env.PARTITION_GRAPH || "../data/graph.json");
const fixture = {
  functions: [{ f: 0 }, { f: 1 }, { f: 2 }],
  files: [{ id: "a.x" }, { id: "inside.x" }, { id: "b.x" }],
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
assert.equal(merged.ports.find((p) => p.direction === "in").name, "Combined");
assert.equal(merged.incoming, b.incoming);
assert.equal(merged.outgoing, b.outgoing);
const ids = new Set(
  D.functions.flatMap((f, i) =>
    D.files[f.f].id === "src/macros/macros.x" ? [i] : [],
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

const twenty = {
  files: Array.from({ length: 6 }, (_, i) => ({ id: `file-${i}.x` })),
  functions: Array.from({ length: 22 }, (_, i) => ({
    f: i < 20 ? Math.floor(i / 4) : 5,
  })),
  edges: Array.from({ length: 20 }, (_, i) => [i, 20, 2]).concat([[0, 21, 3]]),
};
const currentGroups = Array.from({ length: 5 }, (_, i) => ({
  id: `part-${i}`,
  name: `Part ${i}`,
  members: [i * 4, i * 4 + 1, i * 4 + 2, i * 4 + 3],
}));
const targetGroup = { id: "target", name: "Target", members: [20, 21] };
const example = B.collect(twenty, new Set([20, 21]), [
  ...currentGroups,
  targetGroup,
]);
assert.equal(example.ports.length, 5);
assert.deepEqual(
  example.ports.map((p) => p.consumers),
  [4, 4, 4, 4, 4],
);
assert.equal(example.ports[0].calls, 11);
assert.equal(example.incoming, 43);
console.log(
  "PASS: twenty callers in five groups produce five weights of four; repeated sites and targets do not inflate consumers",
);

const splitGroups = currentGroups
  .slice(1)
  .concat([
    { id: "preview-a", name: "Split A", members: [0, 1] },
    { id: "preview-b", name: "Split B", members: [2, 3] },
    targetGroup,
  ]);
const split = B.collect(twenty, new Set([20, 21]), splitGroups);
assert.equal(split.ports.length, 6);
assert(!split.ports.some((p) => p.group === "part-0"));
assert.deepEqual(
  split.ports
    .filter((p) => p.group.startsWith("preview-"))
    .map((p) => [p.name, p.consumers]),
  [
    ["Split A", 2],
    ["Split B", 2],
  ],
);
const combined = B.collect(twenty, new Set([20, 21]), [
  {
    id: "merged",
    name: "Merged callers",
    members: Array.from({ length: 20 }, (_, i) => i),
  },
  targetGroup,
]);
assert.equal(combined.ports.length, 1);
assert.equal(combined.ports[0].consumers, 20);
assert.equal(combined.ports[0].calls, 43);
console.log(
  "PASS: current and preview partitions replace obsolete caller groups after splits and merges",
);
