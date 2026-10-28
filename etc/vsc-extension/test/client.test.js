const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const { selectCompiler, findExecutable } = require("../client");

const settings = (value) => ({ get: (_name, fallback) => value || fallback });

test("compiler discovery preserves explicit selection and workspace executable paths", async (t) => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "x2c lsp discovery "));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const compiler = path.join(root, "x2c");
  assert.equal(selectCompiler(settings("/missing/compiler"), root), "/missing/compiler");
  assert.equal(selectCompiler(settings(), root), "x2c");
  await fs.writeFile(compiler, "#!/bin/sh\nexit 0\n", { mode: 0o700 });
  assert.equal(selectCompiler(settings(), root), compiler);
  assert.equal(selectCompiler(settings()), "x2c");
  assert.equal(findExecutable("x2c", "/", root), compiler);
  assert.equal(findExecutable("./x2c", root, ""), compiler);
  assert.equal(findExecutable(root, "/", ""), null);
});
