import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

test("the playground renders without a compile service", () => {
  const destination = mkdtempSync(join(tmpdir(), "x2c-playground-render-"));
  try {
    const result = spawnSync(process.execPath, [
      "node_modules/astro/bin/astro.mjs", "build", "--outDir", destination,
    ], {
      cwd: fileURLToPath(new URL("..", import.meta.url)),
      env: { ...process.env, PLAYGROUND_URL: "" }, encoding: "utf8",
    });
    assert.equal(result.status, 0, result.stdout + result.stderr);
    const page = readFileSync(join(destination, "playground/index.html"), "utf8");
    assert.match(page, /data-run hidden/);
    assert.match(page, /Running programs is unavailable in this build/);
    assert.match(page, /value="love\/maps"/);
    assert.doesNotMatch(page, /value="power\/threads"/);
    assert.doesNotMatch(page, /value="love\/files"/);
    const home = readFileSync(join(destination, "index.html"), "utf8");
    assert.match(home, /playground\/\?example=love%2Fmaps/);
  } finally {
    rmSync(destination, { recursive: true, force: true });
  }
});
