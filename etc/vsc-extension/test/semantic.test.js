const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const { SemanticService, byteOffset, textOffset, positionAt, runWorker } = require("../semantic");

test("UTF-8 compiler spans map to UTF-16 editor positions across CRLF", () => {
  const text = "/* cafe\u0301 \ud83c\udf0d */\r\nint \u03b1 = 2;";
  const alpha = text.indexOf("\u03b1");
  const start = byteOffset(text, alpha);
  assert.deepEqual(positionAt(text, start), { line: 1, character: 4 });
  assert.deepEqual(positionAt(text, start + 2), { line: 1, character: 5 });
  assert.equal(textOffset(text, start + 1), alpha);
  assert.equal(textOffset(text, 10000), text.length);
  const globe = text.indexOf("\ud83c\udf0d");
  assert.equal(textOffset(text, byteOffset(text, globe + 2)), globe + 2);
});

test("fresh workers receive logical overlays and isolated response files", async (t) => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "x2c-editor-test-"));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const worker = path.join(root, "worker.js");
  await fs.writeFile(worker, `#!/usr/bin/env node
const fs = require('node:fs');
const [response, file, kind, offset, count, ...rest] = process.argv.slice(2);
const overlays = [];
for (let i = 0; i < Number(count); i++) {
  const [logical, snapshot, dirty] = rest.splice(0, 3);
  overlays.push([logical, fs.readFileSync(snapshot, 'utf8'), dirty]);
}
console.log('macro output is not the response');
fs.writeFileSync(response, JSON.stringify({ file, kind, offset, overlays,
  args: rest, pid: process.pid, response, diagnostics: [] }));
`, { mode: 0o700 });
  const service = new SemanticService({ worker, cwd: root,
    args: ["build", "--target", "app", "-DVALUE=2"], tempRoot: root });
  t.after(() => service.dispose());
  const file = path.join(root, 'new "quote\\ and space.x');
  const header = path.join(root, "included.x");
  service.update(file, "int main() {}", 1);
  service.update(header, "", 4);
  const first = await service.analyze(file, "hover", 4);
  const second = await service.analyze(file);
  assert.deepEqual(first.overlays, [[file, "int main() {}", "1"], [header, "", "1"]]);
  assert.deepEqual(first.args, ["--", "build", "--target", "app", "-DVALUE=2"]);
  assert.notEqual(first.pid, second.pid);
  assert.notEqual(first.response, second.response);
  await assert.rejects(fs.stat(path.dirname(first.response)), { code: "ENOENT" });
  assert.equal(first.texts.get(header), "");
});

test("included-file edits cancel and discard an older result", async (t) => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "x2c-editor-test-"));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  let started;
  const ready = new Promise((resolve) => { started = resolve; });
  let complete;
  let observedSignal;
  const service = new SemanticService({ worker: "unused", cwd: root, tempRoot: root,
    run: async (_worker, args, _options, signal) => {
      observedSignal = signal;
      await fs.writeFile(args[0], '{"diagnostics":[]}');
      started();
      return new Promise((resolve) => { complete = resolve; });
    }
  });
  service.update("/project/app.x", "#include \"item.x\"", 1);
  service.update("/project/item.x", "int item;", 1);
  const pending = service.analyze("/project/app.x");
  await ready;
  service.update("/project/item.x", "String item;", 2);
  assert.equal(observedSignal.aborted, true);
  complete({ code: 0 });
  assert.equal(await pending, null);
  assert.deepEqual(await fs.readdir(root), []);
});

test("worker configuration failures remain ordinary editor results", async (t) => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "x2c-editor-test-"));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const service = new SemanticService({ worker: "unused", cwd: root, tempRoot: root,
    run: async () => ({ code: 2, output: "x2c: unknown target 'missing'\n" }) });
  assert.deepEqual(await service.analyze("/app.x"), { error: "x2c: unknown target 'missing'" });
  assert.deepEqual(await fs.readdir(root), []);
});

test("cancelled queries never start a process", async () => {
  const signal = new AbortController();
  signal.abort();
  const service = new SemanticService({ worker: "unused", cwd: os.tmpdir(),
    run: async () => { assert.fail("cancelled query started a worker"); } });
  assert.equal(await service.analyze("/app.x", "hover", 0, signal.signal), null);
});

test("cancellation also stops descendants after their worker exits", {
  skip: process.platform === "win32"
}, async (t) => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "x2c-editor-cancel-"));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const marker = path.join(root, "ready");
  const heartbeat = path.join(root, "heartbeat");
  const childSource = `const fs = require('fs');
    process.on('SIGTERM', () => {});
    setInterval(() => fs.writeFileSync(process.argv[1], String(Date.now())), 10);
    console.log('ready');`;
  const source = `const { spawn } = require('child_process');
    const fs = require('fs');
    const child = spawn(process.execPath, ['-e', ${JSON.stringify(childSource)}, ${JSON.stringify(heartbeat)}],
      { stdio: ['ignore', 'pipe', 'ignore'] });
    child.stdout.once('data', () => fs.writeFileSync(${JSON.stringify(marker)}, String(child.pid)));
    setInterval(() => {}, 1000);`;
  const controller = new AbortController();
  const pending = runWorker(process.execPath, ["-e", source], { cwd: root }, controller.signal);
  t.after(() => controller.abort());
  for (let attempt = 0; attempt < 200; attempt++) {
    try { await fs.stat(marker); break; }
    catch { await new Promise((resolve) => setTimeout(resolve, 10)); }
  }
  await fs.stat(marker);
  controller.abort();
  assert.equal((await pending).cancelled, true);
  await new Promise((resolve) => setTimeout(resolve, 50));
  const first = await fs.readFile(heartbeat, "utf8").catch(() => "");
  await new Promise((resolve) => setTimeout(resolve, 80));
  assert.equal(await fs.readFile(heartbeat, "utf8").catch(() => ""), first);
});
