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
