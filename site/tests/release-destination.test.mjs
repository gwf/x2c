import test from "node:test";
import assert from "node:assert/strict";
import {
  releaseDestination, finalizeDestination, installExample
} from "../release-destination.mjs";

const sha = "a".repeat(40);
const candidate = `candidate-${sha}-42-1`;
const staging = releaseDestination({ SITE_SOURCE_REF: sha,
  SITE_RELEASE_CHANNEL: "staging", SITE_CANDIDATE_ID: candidate });

test("ordinary builds preserve production examples and main links", () => {
  const config = releaseDestination({});
  const html = '<body><a href="https://github.com/gwf/x2c/blob/main/a.x">a</a>';
  assert.equal(finalizeDestination(html, config), html);
  assert.equal(installExample("production command", config), "production command");
});

test("candidate builds pin source links and retain invisible provenance", () => {
  const html = finalizeDestination('<html><head></head><body class="book">' +
    '<a href="https://github.com/gwf/x2c/blob/main/lib/a.x">a</a>' +
    '<a href="https://github.com/gwf/x2c/archive/refs/heads/main.zip">zip</a>',
  staging);
  assert.ok(html.includes(`/blob/${sha}/lib/a.x`));
  assert.ok(html.includes(`/archive/${sha}.zip`));
  assert.ok(!html.includes("/main"));
  assert.ok(html.includes(candidate));
  assert.ok(html.includes('name="x2c-candidate"'));
  assert.ok(!html.includes("<aside"));
  assert.ok(!html.includes("<pre"));
});

test("staging cannot silently use moving main or missing candidate identity", () => {
  assert.throws(() => releaseDestination({ SITE_RELEASE_CHANNEL: "staging" }));
  assert.throws(() => releaseDestination({ SITE_SOURCE_REF: "feature" }));
  assert.throws(() => releaseDestination({ SITE_SOURCE_REF: sha,
    SITE_RELEASE_CHANNEL: "staging" }));
});

test("staging commands use the configured custom domain and root base", async () => {
  const { spawnSync } = await import("node:child_process");
  const result = spawnSync(process.execPath, ["--input-type=module", "-e",
    'import { installExample } from "./site/release-destination.mjs";' +
    'console.log(installExample(""));'], {
    cwd: new URL("../..", import.meta.url), encoding: "utf8",
    env: { ...process.env, SITE_URL: "https://staging.x2c-lang.dev",
      SITE_BASE: "/", SITE_SOURCE_REF: sha, SITE_RELEASE_CHANNEL: "staging",
      SITE_CANDIDATE_ID: candidate }
  });
  assert.equal(result.status, 0, result.stderr);
  assert.ok(result.stdout.includes("https://staging.x2c-lang.dev/install.sh"));
  assert.ok(result.stdout.includes(
    "--index https://staging.x2c-lang.dev/packages/index.txt"));
  assert.ok(!result.stdout.includes("https://x2c-lang.dev"));
});
