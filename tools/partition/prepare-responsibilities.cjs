#!/usr/bin/env node
// Reproduce reviewed assignments; never infer responsibilities from connectivity.
const fs = require("node:fs"),
  path = require("node:path");
global.Engine = require("./web/engine.js");
const R = require("./web/responsibility-model.js");
const data = JSON.parse(
  fs.readFileSync(
    process.env.PARTITION_GRAPH || path.join(__dirname, "data/graph.json"),
  ),
);
for (const file of ["compiler", "macros", "collect"]) {
  const source = path.join(__dirname, "web/responsibilities", file + ".x.json"),
    evidence = JSON.parse(fs.readFileSync(source));
  if (!evidence.revision.startsWith(data.revision))
    throw Error(
      "Review " +
        file +
        " evidence against snapshot " +
        data.revision +
        " before regenerating.",
    );
  const members = data.functions.flatMap((f, v) =>
      data.files[f.f].id === evidence.file ? [v] : [],
    ),
    m = R.create(data, members);
  m.responsibilities = evidence.responsibilities;
  m.constraints = evidence.constraints;
  m.references = evidence.references;
  m.coverage = evidence.coverage;
  for (const o of evidence.operations)
    m.operations[evidence.file + ":" + o.emitted] = o;
  let a = R.analyze(data, m);
  if (a.unreviewed.length)
    throw Error("Missing public operation descriptions in " + file);
  for (const c of a.components) {
    if (c.conflicts.length)
      m.resolutions[c.id] = {
        kind: "module",
        reason: evidence.retainMixedComponents,
      };
    if (c.helperOnly) {
      if (!c.members.some((v) => data.functions[v].k))
        throw Error("Unexplained helper-only component in " + file);
      if (evidence.initialization)
        m.resolutions[c.id] = { kind: "attach", ...evidence.initialization };
    }
  }
  a = R.analyze(data, m);
  for (const r of m.responsibilities) {
    const cs = a.components.filter((c) => c.roles.includes(r.id));
    m.history.push({
      action: "assign components by responsibility",
      responsibility: r.id,
      components: cs.map((c) => c.id),
      reason: r.description + " Evidence: " + r.evidence,
    });
  }
  for (const [id, r] of Object.entries(m.resolutions))
    m.history.push({
      action:
        r.kind === "module" ? "retain module members" : "attach initialization",
      components: [id],
      reason: r.reason,
    });
  fs.writeFileSync(
    path.join(__dirname, "web/responsibilities", file + ".manifest.json"),
    JSON.stringify(m, null, 2) + "\n",
  );
  console.log(
    file +
      ": " +
      a.components.length +
      " components, " +
      a.units.length +
      " candidates, " +
      a.metrics.privateEdges.length +
      " static crossing pairs, " +
      a.metrics.publicEdges.length +
      " public crossing pairs",
  );
}
