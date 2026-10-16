const assert = require("node:assert/strict"),
  L = require("../web/layout.js"),
  E = require("../web/engine.js"),
  D = require(process.env.PARTITION_GRAPH || "../data/graph.json");
const previousLayout = require("./layout-baseline.cjs");
for (const file of ["src/transform/transform.x", "src/compiler/compiler.x", "lib/typed-array.x"]) {
  const fi = D.files.findIndex((f) => f.id === file),
    members = D.functions.flatMap((f, i) => (f.f === fi ? [i] : [])),
    parts = [0, 1, 2].map(n => members.filter((_, i) => i % 3 === n)),
    gs = parts.map((members, i) => ({ id: String(i), name: file, members }));
  const old = previousLayout(gs, D),
    before = L.quality(old.nodes, old.edges);
  const groups = gs.map((g) => ({
      ...g,
      nodes: g.members.map((id) => ({ id, name: D.functions[id].n })),
    })),
    start = performance.now(),
    out = L.solve(groups, D.edges, 1.5),
    ms = Math.round(performance.now() - start);
  assert.deepEqual(
    out.nodes.map((n) => n.id).sort((a, b) => a - b),
    members.slice().sort((a, b) => a - b),
  );
  assert(out.nodes.every((n) => Number.isFinite(n.x) && Number.isFinite(n.y)));
  assert.equal(out.after.overlaps, 0);
  for (const n of out.nodes) {
    const r = out.regions[n.group];
    assert(n.x >= r.x && n.x <= r.x + r.w && n.y >= r.y && n.y <= r.y + r.h);
  }
  for (let a = 0; a < out.regions.length; a++)
    for (let b = a + 1; b < out.regions.length; b++) {
      const A = out.regions[a],
        B = out.regions[b];
      assert(
        A.x + A.w <= B.x ||
          B.x + B.w <= A.x ||
          A.y + A.h <= B.y ||
          B.y + B.h <= A.y,
      );
    }
  assert(out.after.crossings < before.crossings);
  console.log(
    `${file}: ${members.length} functions; old ${before.crossings} crossings; new ${out.after.crossings}; 0 label-box overlaps; ${ms} ms.`,
  );
}
