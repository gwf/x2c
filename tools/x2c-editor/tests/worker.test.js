const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const { SemanticService, byteOffset } = require("../../../etc/vsc-extension/semantic");

const prefix = process.env.X2C_EDITOR_COMPILER ? ["editor"] : [];
const worker = process.env.X2C_EDITOR_COMPILER || process.env.X2C_EDITOR_WORKER ||
  path.resolve(__dirname, "../builds/x2c-editor-worker");

async function workspace(t) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "x2c-editor-native-"));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  return root;
}

function configured(t, root, args) {
  const service = new SemanticService({ worker, prefix, cwd: root, args });
  t.after(() => service.dispose());
  return service;
}

test("native worker resolves lexical definitions and hover from unsaved text", async (t) => {
  const root = await workspace(t);
  const file = path.join(root, 'new "quote\\ and space.x');
  const text = "int main(void) {\n  int value = 3;\n  { int value = 4; value++; }\n  return value;\n}\n";
  const service = configured(t, root, ["translate", file]);
  service.update(file, text, 1);
  const inner = await service.analyze(file, "definition", byteOffset(text, text.indexOf("value++")));
  assert.equal(inner.error, undefined);
  assert.equal(inner.definition.start, byteOffset(text, text.indexOf("value = 4")));
  const outer = await service.analyze(file, "definition", byteOffset(text, text.lastIndexOf("value")));
  assert.equal(outer.definition.start, byteOffset(text, text.indexOf("value = 3")));
  const hover = await service.analyze(file, "hover", byteOffset(text, text.lastIndexOf("value")));
  assert.match(hover.hover.text, /int\s+value/);
});

test("included overlays update declaration locations without touching disk", async (t) => {
  const root = await workspace(t);
  const file = path.join(root, "main.x");
  const header = path.join(root, "included.x");
  const text = '#include "included.x"\nint main(void) { return supplied; }\n';
  await fs.writeFile(header, "int supplied;\n");
  const service = configured(t, root, ["translate", file]);
  service.update(file, text, 1);
  service.update(header, "int supplied;\n", 1, false);
  const offset = byteOffset(text, text.indexOf("supplied"));
  const before = await service.analyze(file, "definition", offset);
  assert.equal(before.error, undefined);
  assert.equal(before.definition.start, 4);
  service.update(header, "\n\nint supplied;\n", 2);
  const after = await service.analyze(file, "definition", offset);
  assert.equal(after.definition.start, 6);
  assert.equal(after.sources.find((source) => source.file === after.definition.file).text,
    "\n\nint supplied;\n");
  assert.equal(await fs.readFile(header, "utf8"), "int supplied;\n");
});

test("a kept macro declaration retains its included source definition", async (t) => {
  const root = await workspace(t);
  const file = path.join(root, "main.x");
  const header = path.join(root, "kept.x");
  const helper = path.join(root, "keep.xmacro");
  const text = '#include "kept.x"\nint main(void) { return supplied; }\n';
  const macro = 'macro Unit $keep(Decl $target) => { $target }\n';
  const included = '$(import "keep.xmacro")\n$keep(int supplied);\n';
  const service = configured(t, root, ["translate", file]);
  service.update(file, text, 1);
  service.update(header, included, 1);
  service.update(helper, macro, 1);
  const result = await service.analyze(file, "definition", byteOffset(text, text.indexOf("supplied")));
  assert.equal(result.error, undefined);
  assert.ok(result.definition);
  assert.equal(path.basename(result.definition.file), "kept.x");
  assert.equal(result.definition.start, byteOffset(included, included.indexOf("supplied")));
  // Collection intentionally skips local Unit expansions without protocol
  // rows. Such a forward spelling has no declaration location to invent.
  service.update(header, macro + "$keep(int supplied);\n", 2);
  const skipped = await service.analyze(file, "definition", byteOffset(text, text.indexOf("supplied")));
  assert.equal(skipped.error, undefined);
  assert.equal(skipped.definition, undefined);
  const unknown = await service.analyze(file, "hover", byteOffset(text, text.indexOf("supplied")));
  assert.equal(unknown.hover, undefined);
});

test("a discarded macro declaration cannot navigate to a later reused binding", async (t) => {
  const root = await workspace(t);
  const file = path.join(root, "main.x");
  const text = 'macro Unit $drop(Decl $target) => {}\n$drop(int erased);\n' +
    'int erased;\nint main(void) { return erased; }\n';
  const service = configured(t, root, ["translate", file]);
  service.update(file, text, 1);
  const result = await service.analyze(file, "definition", byteOffset(text, text.indexOf("erased")));
  assert.equal(result.error, undefined);
  assert.equal(result.definition, undefined);
});

test("malformed input retains diagnostics and a later fresh request recovers", async (t) => {
  const root = await workspace(t);
  const file = path.join(root, "main.x");
  const service = configured(t, root, ["translate", file]);
  service.update(file, "int main(void) {", 1);
  const broken = await service.analyze(file);
  assert.equal(broken.error, undefined);
  assert.ok(broken.diagnostics.length > 0);
  service.update(file, "int main(void) { return 0; }", 2);
  const repaired = await service.analyze(file);
  assert.equal(repaired.error, undefined);
  assert.deepEqual(repaired.diagnostics, []);
});

test("package aliases resolve through effective manifest package settings", async (t) => {
  const root = await workspace(t);
  const file = path.join(root, "main.x");
  const packages = path.join(root, "packages");
  const entry = path.join(packages, "toy", "toy.x");
  const manifest = path.join(root, "x2c.toml");
  const text = 'import "toy" as t;\nint main(void) { return t.answer(); }\n';
  const configuration = '[project]\ndefault-target = "app"\n[target.app]\n' +
    'sources = ["main.x"]\npackage-dirs = ["packages"]\n';
  await fs.mkdir(path.dirname(entry), { recursive: true });
  await fs.writeFile(entry, "int answer(void);\n");
  await fs.writeFile(file, text);
  await fs.writeFile(manifest, configuration);
  const service = configured(t, root, []);
  service.update(file, text, 1, false);
  service.update(entry, "\nint answer(void);\n", 2);
  const result = await service.analyze(file, "definition", byteOffset(text, text.indexOf("answer")));
  assert.equal(result.error, undefined);
  assert.equal(result.definition.start, 5);
  assert.equal(path.basename(result.definition.file), "toy.x");
  service.update(manifest, "[project", 2);
  assert.ok((await service.analyze(file)).error, "unsaved malformed manifest must be read");
  service.update(manifest, configuration, 3);
  assert.equal((await service.analyze(file)).error, undefined);
});

test("unsaved macro import errors remain inspectable and repairable", async (t) => {
  const root = await workspace(t);
  const file = path.join(root, "main.x");
  const macro = path.join(root, "helper.xmacro");
  const definition = "macro Expression $twice($value) => ($value + $value)\n";
  const text = '$(import "helper.xmacro")\nint main(void) { return $twice(2); }\n';
  await fs.writeFile(macro, definition);
  const service = configured(t, root, ["translate", file]);
  service.update(file, text, 1);
  service.update(macro, "macro Expression $twice($value) => (", 2);
  const broken = await service.analyze(file);
  assert.equal(broken.error, undefined);
  assert.ok(broken.diagnostics.length > 0);
  service.update(macro, definition, 3);
  const repaired = await service.analyze(file);
  assert.equal(repaired.error, undefined);
  assert.deepEqual(repaired.diagnostics, []);
});

test("project errors stay in the service", async (t) => {
  const root = await workspace(t);
  const file = path.join(root, "main.x");
  const service = configured(t, root, ["build", "--manifest-path", path.join(root, "missing.toml")]);
  service.update(file, "int main(void) { return 0; }", 1);
  assert.match((await service.analyze(file)).error, /manifest/);
});

test("an unrelated dirty file does not disturb a saved unit", async (t) => {
  const root = await workspace(t);
  const file = path.join(root, "main.x");
  const header = path.join(root, "input.h");
  const text = '#include "input.h"\nint main(void) { return answer; }\n';
  await fs.writeFile(file, text);
  await fs.writeFile(header, "int answer;\n");
  const service = configured(t, root, ["translate", file]);
  service.update(file, text, 1, false);
  service.update(path.join(root, "unrelated.x"), "int unrelated;", 1);
  const saved = await service.analyze(file);
  assert.equal(saved.error, undefined);
  assert.deepEqual(saved.diagnostics, []);
  const definition = await service.analyze(file, "definition", byteOffset(text, text.indexOf("answer")));
  assert.equal(path.basename(definition.definition.file), "input.h");
  assert.equal(definition.definition.start, 4);
  assert.equal(definition.definition.end, 10);
});
