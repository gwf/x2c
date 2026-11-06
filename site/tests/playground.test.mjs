import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const site = fileURLToPath(new URL("..", import.meta.url));
const emcc =
  spawnSync(process.env.WASM_CC || "emcc", ["--version"]).status === 0;

// Prepares the precompiled programs, builds the site without a compile
// service, and returns the playground page and homepage.
function render(env) {
  const prepared = spawnSync(process.execPath, [
    "scripts/playground-programs.mjs", "compile",
  ], { cwd: site, env: { ...process.env, ...env }, encoding: "utf8" });
  assert.equal(prepared.status, 0, prepared.stdout + prepared.stderr);
  const destination = mkdtempSync(join(tmpdir(), "x2c-playground-render-"));
  try {
    const result = spawnSync(process.execPath, [
      "node_modules/astro/bin/astro.mjs", "build", "--outDir", destination,
    ], {
      cwd: site, env: { ...process.env, PLAYGROUND_URL: "" },
      encoding: "utf8",
    });
    assert.equal(result.status, 0, result.stdout + result.stderr);
    return {
      page: readFileSync(join(destination, "playground/index.html"), "utf8"),
      home: readFileSync(join(destination, "index.html"), "utf8"),
    };
  } finally {
    rmSync(destination, { recursive: true, force: true });
  }
}

test("without programs or a service, the playground is unlinked", () => {
  const { page, home } = render({ WASM_CC: "x2c-missing-emcc" });
  assert.match(page, /data-run hidden/);
  assert.match(page, /Running programs is unavailable in this build/);
  assert.match(page, /value="love\/maps"/);
  assert.doesNotMatch(page, /value="power\/threads"/);
  assert.doesNotMatch(page, /value="love\/files"/);
  assert.doesNotMatch(page, /data-programs/);
  assert.doesNotMatch(home, /playground\//);
});

test("precompiled programs run the examples without a compile service",
  { skip: !emcc && "emcc is not on PATH" }, () => {
    const { page, home } = render({});
    assert.doesNotMatch(page, /data-run hidden/);
    assert.match(page, /data-programs="[^"]*playground\/programs\/"/);
    assert.match(page, /this build has no compile service/);
    assert.doesNotMatch(page, /Source is sent to the compile service/);
    assert.match(page, /value="love\/maps"/);
    assert.doesNotMatch(page, /value="power\/threads"/);
    // The editor shows the slide's code; the program keeps its hidden lines.
    const examples = JSON.parse(page.match(
      /<script type="application\/json" data-examples>([\s\S]*?)<\//)[1]);
    const maps = examples.find((example) => example.id === "love/maps");
    assert.equal(maps.program, true);
    assert.match(maps.source, /int main\(void\)/);
    assert.doesNotMatch(maps.visible, /int main\(void\)/);
    assert.match(home, /playground\/\?example=love%2Fmaps/);
    assert.match(home, /href="[^"]*playground\/">playground</);
  });
