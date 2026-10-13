// Validate reviewed responsibility manifests against their source snapshot.
const fs = require("node:fs"),
  path = require("node:path"),
  assert = require("node:assert/strict");
global.Engine = require("../web/engine.js");
const R = require("../web/responsibility-model.js");
const D = require(process.env.PARTITION_GRAPH || "../data/graph.json");
for (const file of ["compiler", "macros", "collect"]) {
  const m = JSON.parse(
    fs.readFileSync(
      path.join(__dirname, "../web/responsibilities", file + ".manifest.json"),
    ),
  );
  const a = R.analyze(D, m);
  assert(a.valid);
  assert.equal(a.unreviewed.length, 0);
  assert.equal(a.metrics.privateEdges.length, 0);
  assert(a.unresolvedConstraints.length > 0);
  assert.equal(a.canApply, false);
  const expected = D.functions.flatMap((f, v) =>
    D.files[f.f].id === "src/" + file + ".x" ? [v] : [],
  );
  assert.deepEqual(
    a.units.flatMap((u) => u.members).sort((a, b) => a - b),
    expected,
  );
  for (const c of a.components)
    for (const conflict of c.conflicts) {
      assert(conflict.path.length);
      assert.equal(conflict.path[0].from, conflict.a);
      assert.equal(conflict.path.at(-1).to, conflict.b);
    }
  for (const r of m.references) {
    assert(
      a.components.some((c) =>
        [r.from, r.to].every((k) => c.members.some((v) => R.key(D, v) === k)),
      ),
    );
  }
  if (file !== "compiler")
    assert(a.units.some((u) => u.moduleMembers.length >= 10));
  console.log(
    `${file}: ${Object.keys(m.operations).length} described operations, ${m.responsibilities.length} responsibilities, ${a.components.length} components, ${a.units.length} proposed containers; ${a.unresolvedConstraints.length} unresolved declaration constraints. All functions assigned once.`,
  );
}
const reference = require("../web/fixtures/compiler-responsibilities.json");
if (!reference.revision.startsWith(D.revision))
  throw Error("Reference requires its original snapshot.");
const ids = new Map(
  D.functions.flatMap((f, v) =>
    D.files[f.f].id === reference.file ? [[f.e, v]] : [],
  ),
);
const parts = reference.groups.map((g) => g.functions.map((f) => ids.get(f.e)));
assert.equal(new Set(parts.flat()).size, 189);
const metrics = Engine.decomposition(D, parts);
assert.deepEqual(
  [metrics.pairs, metrics.calls, metrics.privateTargets],
  [20, 21, 0],
);
console.log(
  "Compiler eight-group reference reproduced independently; it does not generate assignments.",
);
