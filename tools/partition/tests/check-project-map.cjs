const assert = require("node:assert/strict");
const layout = require("../web/project-map.js");
const data = require(process.env.PARTITION_GRAPH || "../data/graph.json");
const nodes = data.files.map((f) => ({
  r: Math.max(5, Math.sqrt(f.lines) * 0.72),
}));
const links = data.fileEdges.map((e) => ({ ids: [e.s, e.t], w: e.calls }));
const result = layout(nodes, links);
assert.equal(result.length, nodes.length);
assert.deepEqual(result, layout(nodes, links));
for (let i = 0; i < result.length; i++) {
  const a = result[i];
  assert(Number.isFinite(a.x) && Number.isFinite(a.y));
  for (let j = i + 1; j < result.length; j++) {
    const b = result[j];
    assert(
      Math.hypot(a.x - b.x, a.y - b.y) >= a.r + b.r,
      "overlapping file nodes",
    );
  }
}
console.log(
  "PASS: deterministic project layout, complete membership, no disk overlaps",
);

// Scoped groups retain direction and weight without phantom outside nodes.
const quotient = layout.aggregateGroupCalls(
  {
    edges: [
      [0, 1, 2],
      [0, 2, 3],
      [2, 0, 4],
      [3, 1, 5],
      [0, 4, 6],
      [1, 0, 7],
    ],
  },
  [{ members: [0, 1] }, { members: [2] }],
);
assert.deepEqual(quotient.links, [
  { ids: [0, 1], w: 3 },
  { ids: [1, 0], w: 4 },
]);
assert.deepEqual(quotient.callers, [2, 1]);
assert.deepEqual(quotient.incoming, [9, 3]);
assert.equal(layout([{ r: 10 }], []).length, 1);
console.log("PASS: scoped directed aggregation and incoming consumers");
const context = layout.arrangementData(
  {
    functions: [{}, {}, {}, {}],
    edges: [
      [2, 0, 2],
      [2, 1, 3],
      [3, 1, 4],
      [0, 2, 8],
    ],
  },
  [
    { id: "a", members: [0] },
    { id: "b", members: [1] },
  ],
  [
    { id: "a", members: [0] },
    { id: "b", members: [1] },
    { id: "outside-current", members: [2, 3] },
  ],
);
assert.equal(context.groups.length, 3);
assert.equal(context.groups[2].id, "outside-current");
assert.equal(context.groups[2].consumerCount, 2);
assert.deepEqual(context.links, [
  { ids: [2, 0], w: 1, calls: 2, outside: true },
  { ids: [2, 1], w: 2, calls: 7, outside: true },
]);
console.log(
  "PASS: collapsed outside groups have deduplicated caller weights and no outgoing callee links",
);
