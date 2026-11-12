import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import test, { after } from "node:test";

const site = fileURLToPath(new URL("..", import.meta.url));
const emcc =
  spawnSync(process.env.WASM_CC || "emcc", ["--version"]).status === 0;

// These tests rerun compile, which removes the shared program list when it
// cannot build; restore the list the developer's tree had.
const manifest = join(site, "../builds/wasm/playground/programs.json");
const saved = existsSync(manifest) ? readFileSync(manifest) : undefined;
after(() => { if (saved) writeFileSync(manifest, saved); });

// Prepares the precompiled programs, builds the site without a compile
// service, and returns the redirect, complete examples, and homepage.
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
      love: readFileSync(join(destination, "examples/love/index.html"), "utf8"),
      magic: readFileSync(join(destination, "examples/magic/index.html"), "utf8"),
      home: readFileSync(join(destination, "index.html"), "utf8"),
    };
  } finally {
    rmSync(destination, { recursive: true, force: true });
  }
}

test("without WebAssembly, galleries still link to complete examples", () => {
  const { page, home, love, magic } = render({ WASM_CC: "x2c-missing-emcc" });
  assert.doesNotMatch(page, /textarea|data-run|<select/);
  assert.match(page, /location.replace/);
  assert.match(page, /"love\/values":"love\/#love-values"/);
  assert.doesNotMatch(home, /Run in playground|playground\//);
  assert.match(home, /examples\/love\/#love-values/);
  assert.match(home, /examples\/magic\/#magic-autodiff/);
  assert.match(love, /id="love-values"/);
  assert.match(magic, /packages\/autodiff\/examples\/energy-gradient.x/);
});

test("complete examples retain precompiled programs and expected output",
  { skip: !emcc && "emcc is not on PATH" }, () => {
    const { page, home, love } = render({});
    assert.doesNotMatch(page, /data-playground/);
    assert.match(love, /data-programs="[^"]*playground\/programs\/"/);
    const examples = [...love.matchAll(
      /<script type="application\/json" data-examples>([\s\S]*?)<\//g)]
      .flatMap(match => JSON.parse(match[1]));
    const maps = examples.find(example => example.id === "love/maps");
    assert.equal(maps.program, true);
    assert.equal(maps.source, readFileSync(join(site, "../examples/love/maps.x"), "utf8"));
    assert.match(maps.source, /int main\(void\)/);
    assert.match(love, /data-expected-output/);
    assert.match(home, /examples\/love\/#love-collections/);
  });


test("deployment builds reject missing WebAssembly prerequisites", () => {
  const result = spawnSync(process.execPath, [
    "scripts/playground-programs.mjs", "compile",
  ], { cwd: site, encoding: "utf8", env: { ...process.env,
    PLAYGROUND_REQUIRED: "1", WASM_CC: "x2c-missing-emcc" } });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /required programs unavailable/);
});
