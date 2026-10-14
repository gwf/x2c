const assert = require("node:assert/strict");
global.Engine = require("../web/engine.js");
const R = require("../web/responsibility-model.js");
const D = {
  revision: "fixture",
  files: [{ id: "src/a.x" }],
  functions: ["publicA", "publicB", "helper", "callback", "publicC"].map(
    (e, i) => ({ e, n: e, f: 0, s: i === 2 || i === 3, o: i }),
  ),
  edges: [
    [0, 2, 1],
    [1, 2, 1],
    [0, 4, 99],
  ],
};
const m = R.create(D, [0, 1, 2, 3, 4]);
m.coverage = "Fixture has complete calls and the recorded callback reference.";
m.responsibilities = [
  {
    id: "a",
    name: "Parse declarations",
    description: "Parse declarations",
    evidence: "body",
  },
  {
    id: "b",
    name: "Write declarations",
    description: "Write declarations",
    evidence: "body",
  },
  { id: "c", name: "Read paths", description: "Read paths", evidence: "body" },
];
for (const [v, responsibility] of [
  [0, "a"],
  [1, "b"],
  [4, "c"],
])
  m.operations[R.key(D, v)] = {
    operation: "Operation",
    state: "state",
    phase: "phase",
    section: "section",
    evidence: "body + callers",
    responsibility,
  };
m.references = [
  { from: R.key(D, 0), to: R.key(D, 3), evidence: "callback registration" },
];
let a = R.analyze(D, m);
assert.equal(a.components.length, 2);
assert.equal(a.unreviewed.length, 0);
assert.equal(a.canApply, false);
const conflict = a.components.find((c) => c.conflicts.length);
assert.equal(conflict.conflicts[0].path.length, 2);
assert(conflict.members.includes(3));
m.resolutions[conflict.id] = {
  kind: "module",
  reason: "Read and write operations share the private declaration helper.",
};
a = R.analyze(D, m);
assert(a.canApply);
assert.equal(a.units.length, 2);
assert.equal(a.metrics.publicEdges.length, 1);
assert(a.units.some((u) => u.moduleMembers.length === 2));
assert(a.valid);
// Public calls do not merge responsibilities, regardless of their weight.
assert(a.units.some((u) => u.members.length === 1 && u.members[0] === 4));
const restored = JSON.parse(JSON.stringify(m));
assert.deepEqual(R.analyze(D, restored), a);
R.merge(
  m,
  ["a", "b"],
  "Process declarations",
  "Read and write declarations",
  "Both own declaration lifetime",
  [conflict.id],
);
a = R.analyze(D, m);
assert.equal(a.components[0].conflicts.length, 0);
assert.equal(m.history[0].components[0], conflict.id);
assert.throws(
  () => R.analyze(D, { ...m, scope: [...m.scope, m.scope[0]] }),
  /membership/,
);
assert.throws(() => R.analyze(D, { ...m, revision: "old" }), /snapshot/);
// Incomplete scopes cannot silently split private components.
const partial = { ...m, scope: [R.key(D, 0)] };
assert(!R.analyze(D, partial).canApply);
// An orphan static needs an explicit execution/accessibility explanation.
const orphan = R.create(D, [3]);
assert(!R.analyze(D, orphan).canApply);
console.log(
  "PASS: operation assignments, exact helper paths, callbacks, module decisions, public crossings, manifests, incomplete scopes, orphan helpers",
);
// Unknown private declarations prevent claiming completed separate units.
m.constraints = [
  {
    kind: "macro",
    symbol: "REPORT",
    status: "unresolved",
    evidence: "Uses need ownership review",
  },
];
a = R.analyze(D, m);
assert(!a.canApply);
assert(a.units.every((u) => u.classification === "Unassigned or unresolved"));
const blank = JSON.parse(JSON.stringify(m));
blank.constraints = [];
blank.responsibilities[0].description = "";
assert(R.analyze(D, blank).unreviewed.length);
// Merging responsibilities updates helper-only attachments too.
const attached = R.create(D, [3]);
attached.responsibilities = m.responsibilities;
let ac = R.analyze(D, attached).components[0];
attached.resolutions[ac.id] = {
  kind: "attach",
  responsibility: "a",
  reason: "Registered callback retained with declaration lifetime",
};
R.merge(
  attached,
  ["c", "a"],
  "Combined",
  "Combined operations",
  "Common owner",
  [ac.id],
);
assert.equal(attached.resolutions[ac.id].responsibility, "c");
const unreasoned = JSON.parse(JSON.stringify(restored));
unreasoned.resolutions[conflict.id] = { kind: "module" };
assert(!R.analyze(D, unreasoned).canApply);
attached.coverage = "Fixture contains only this registered callback.";
attached.responsibilities[0].description = "";
assert(!R.analyze(D, attached).canApply);

// A missing agent reference must preserve the proposal and block extraction,
// while a recognized callback must still keep its private component intact.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {execFileSync} = require('node:child_process');
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'partition-reference-test-'));
try {
  const proposal = {
    ...restored,
    operations: Object.entries(restored.operations).map(([key, op]) => ({...op, key})),
    references: [...restored.references, {from: R.key(D, 0), to: 'external:unknown_callback', evidence: 'registration line 12'}],
    moduleArrangement: restored.responsibilities.map(r => ({
      responsibility: r.id,
      members: r.id === 'a' ? [0,2,3].map(v => R.key(D,v)) : [r.id === 'b' ? 1 : 4].map(v => R.key(D,v)),
      evidence: 'Fixture source ownership',
    })),
  };
  for (const [name, value] of Object.entries({graph: D, scope: restored.scope, answer: proposal}))
    fs.writeFileSync(path.join(directory, name + '.json'), JSON.stringify(value));
  const converted = JSON.parse(execFileSync(process.execPath, [path.join(__dirname, '../analyze-responsibilities.cjs'), ...['graph','scope','answer'].map(n => path.join(directory,n+'.json'))], {encoding:'utf8'}));
  const analyzed = R.analyze(D, converted);
  assert(analyzed.valid);
  assert(!analyzed.canApply);
  assert(analyzed.components.some(c => c.members.includes(0) && c.members.includes(3)));
  assert.equal(analyzed.unresolvedConstraints.length, 1);
  assert.match(analyzed.unresolvedConstraints[0].symbol, /external:unknown_callback/);
  assert.match(analyzed.unresolvedConstraints[0].evidence, /registration line 12/);
  assert.equal(R.moduleUnits(D, converted).flatMap(g => g.members).length, 5);
  console.log('PASS: unknown agent references remain visible without losing assignments or known private constraints');
} finally {
  fs.rmSync(directory, {recursive:true, force:true});
  fs.rmSync(path.join(__dirname, '../data/analysis-responses', path.basename(directory)), {recursive:true, force:true});
}
