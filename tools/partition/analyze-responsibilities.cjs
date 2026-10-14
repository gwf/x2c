#!/usr/bin/env node
// Convert source analysis into the same validated manifest used by the browser.
const fs = require('node:fs');
global.Engine = require('./web/engine.js');
const R = require('./web/responsibility-model.js');
const [graphPath, scopePath, answerPath] = process.argv.slice(2);
const data = JSON.parse(fs.readFileSync(graphPath));
const scope = JSON.parse(fs.readFileSync(scopePath));
const raw = fs.readFileSync(answerPath, 'utf8').trim().replace(/^```(?:json)?\s*/, '').replace(/\s*```$/, '');
const answer = JSON.parse(raw);
const ids = new Map(data.functions.map((_, v) => [R.key(data, v), v]));
const m = R.create(data, scope.map(k => ids.get(k)));
const expected = scope.filter(k => {
  const f = data.functions[ids.get(k)];
  return !f.s && !f.k;
});
if (!Array.isArray(answer.operations) || answer.operations.length !== expected.length ||
    new Set(answer.operations.map(o => o.key)).size !== expected.length ||
    answer.operations.some(o => !expected.includes(o.key)))
  throw Error('Agent analysis must describe every selected public operation exactly once.');
m.responsibilities = answer.responsibilities;
m.operations = Object.fromEntries(answer.operations.map(o => [o.key, o]));
m.constraints = answer.constraints;
m.references = answer.references;
m.coverage = answer.coverage;
let a = R.analyze(data, m);
if (a.unreviewed.length) throw Error(`Agent analysis is incomplete: ${a.unreviewed.length} public operations are missing evidence or assignments.`);
for (const c of a.components) {
  if (c.conflicts.length) m.resolutions[c.id] = {
    kind: 'module',
    reason: 'Retain these responsibilities within one translation unit because the recorded private dependency paths join their public operations. No helper is made public.',
  };
  if (c.helperOnly) {
    const attachment = (answer.attachments || []).find(x => c.members.some(v => R.key(data, v) === x.function));
    if (attachment) m.resolutions[c.id] = {kind: 'attach', responsibility: attachment.responsibility, reason: attachment.reason};
  }
}
a = R.analyze(data, m);
if (!a.valid || a.metrics.privateEdges.length) throw Error('Agent proposal fails private dependency validation.');
for (const r of m.responsibilities) m.history.push({
  action: 'agent source analysis', responsibility: r.id,
  components: a.components.filter(c => c.roles.includes(r.id)).map(c => c.id),
  reason: r.description + ' Evidence: ' + r.evidence,
});
for (const [id, resolution] of Object.entries(m.resolutions)) m.history.push({action: 'retain private dependency component', components: [id], reason: resolution.reason});
process.stdout.write(JSON.stringify(m));
