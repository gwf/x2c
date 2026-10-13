// Optional snapshot-bound comparison; no source writes or compiler probes.
const E = require("../web/engine.js");
const D = require(process.env.PARTITION_GRAPH || "../data/graph.json");
const reference = require("../web/fixtures/compiler-responsibilities.json");
console.log("Snapshot:", D.revision);
for (const file of ["src/compiler.x", "src/macros.x", "src/collect.x"]) {
  const fi = D.files.findIndex((f) => f.id === file),
    all = D.functions.flatMap((f, v) => (f.f === fi ? [v] : [])),
    authored = all.filter((v) => !D.functions[v].k),
    ties = E.privacyTies(D);
  const components = E.atoms(authored, ties);
  console.log(
    file,
    "authored",
    authored.length,
    "top-level",
    all.length - authored.length,
    "components",
    components.length,
    "largest",
    Math.max(...components.map((c) => c.length)),
  );
  for (const [mode, t, constraints] of [
    ["ordinary", 0, []],
    ["ordinary", 0.3, []],
    ["privacy", 0, ties],
    ["privacy", 0.3, ties],
  ]) {
    const p = E.partition(D, authored, 8, t, constraints),
      m = E.decomposition(D, p);
    console.log(
      mode,
      t,
      JSON.stringify({
        sizes: p.map((c) => c.length),
        pairs: m.pairs,
        calls: m.calls,
        staticTargets: m.privateTargets,
      }),
    );
  }
  if (file === reference.file && reference.revision.startsWith(D.revision)) {
    const ids = new Map(authored.map((v) => [D.functions[v].e, v]));
    const p = reference.groups.map((g) => g.functions.map((f) => ids.get(f.e)));
    if (p.flat().some((v) => v === undefined))
      throw Error("Reference identities differ");
    const m = E.decomposition(D, p);
    console.log(
      "semantic reference",
      JSON.stringify({
        sizes: p.map((c) => c.length),
        pairs: m.pairs,
        calls: m.calls,
        staticTargets: m.privateTargets,
      }),
    );
    const owner = new Map(
      p.flatMap((c, i) => c.map((v) => [v, reference.groups[i].name])),
    );
    for (const [i, c] of E.partition(D, authored, 8, 0.3, ties).entries()) {
      const counts = {};
      for (const v of c) counts[owner.get(v)] = (counts[owner.get(v)] || 0) + 1;
      console.log("automatic group", i + 1, counts);
    }
  }
  const m = E.decomposition(D, [all]);
  console.log(
    "top-level references",
    m.topEdges.map(([a, b, w]) => [D.functions[a].n, D.functions[b].n, w]),
  );
}
