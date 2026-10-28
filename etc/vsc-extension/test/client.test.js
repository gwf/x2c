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

test("canonical server URIs keep the workspace directory alias and leave external resources unchanged", async (t) => {
  const { pathToFileURL, fileURLToPath } = require("node:url");
  const nativeFs = require("node:fs");
  const { uriConverters } = require("../client");
  const Uri = {
    file(file) {
      const url = pathToFileURL(file);
      return { scheme: "file", fsPath: fileURLToPath(url), toString: () => url.href };
    },
    parse(value) {
      const url = new URL(value);
      return { scheme: url.protocol.slice(0, -1),
        fsPath: url.protocol === "file:" ? fileURLToPath(url) : undefined,
        toString: () => url.href };
    }
  };
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "x2c-uri-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const real = path.join(directory, "real"), alias = path.join(directory, "workspace");
  await fs.mkdir(real);
  await fs.symlink(real, alias, "dir");
  const canonical = nativeFs.realpathSync(real);
  const converters = uriConverters(alias, Uri);
  const filename = "file # name.x";
  const logical = Uri.file(path.join(alias, filename));
  const physical = Uri.file(path.join(canonical, filename));
  assert.equal(converters.code2Protocol(logical), logical.toString());
  assert.equal(converters.protocol2Code(physical.toString()).toString(), logical.toString());
  assert.equal(converters.protocol2Code(Uri.file(canonical).toString()).fsPath, alias);
  for (const outside of [Uri.file(path.join(canonical + "-other", filename)),
    Uri.file(path.join(directory, "external.x")), Uri.parse("untitled:buffer")])
    assert.equal(converters.protocol2Code(outside.toString()).toString(), outside.toString());
});
