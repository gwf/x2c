import test from "node:test";
import assert from "node:assert/strict";
import {
  releaseDestination, finalizeDestination, robotsText
} from "../release-destination.mjs";

const sha = "a".repeat(40);
const candidate = `candidate-${sha}-42-1`;
const staging = releaseDestination({ SITE_SOURCE_REF: sha,
  SITE_RELEASE_CHANNEL: "staging", SITE_CANDIDATE_ID: candidate });

test("ordinary builds preserve production examples and main links", () => {
  const config = releaseDestination({});
  const html = '<body><a href="https://github.com/gwf/x2c/blob/main/a.x">a</a>';
  assert.equal(finalizeDestination(html, config), html);
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
  assert.ok(html.includes('<meta name="robots" content="noindex">'));
  assert.ok(!html.includes("<aside"));
  assert.ok(!html.includes("<pre"));
});

test("only staging disallows crawlers", () => {
  assert.ok(robotsText(releaseDestination({})).includes("Allow: /"));
  assert.ok(robotsText(staging).includes("Disallow: /"));
  assert.ok(!robotsText(staging).includes("Sitemap"));
});

test("staging cannot silently use moving main or missing candidate identity", () => {
  assert.throws(() => releaseDestination({ SITE_RELEASE_CHANNEL: "staging" }));
  assert.throws(() => releaseDestination({ SITE_SOURCE_REF: "feature" }));
  assert.throws(() => releaseDestination({ SITE_SOURCE_REF: sha,
    SITE_RELEASE_CHANNEL: "staging" }));
});

test("website-only staging separates website source from retained release", () => {
  const website = "b".repeat(40);
  const config = releaseDestination({ SITE_SOURCE_REF: website,
    SITE_STAGED_SOURCE_REF: sha, SITE_RELEASE_CHANNEL: "staging",
    SITE_CANDIDATE_ID: candidate });
  const html = finalizeDestination('<html><head></head><body>' +
    '<a href="https://github.com/gwf/x2c/blob/main/example.x">source</a>', config);
  assert.ok(html.includes(`/blob/${website}/example.x`));
  assert.ok(html.includes(`name="x2c-site-source" content="${website}"`));
  assert.ok(html.includes(`name="x2c-candidate" content="${candidate}"`));
  assert.equal(config.releaseRef, sha);
  const production = releaseDestination({ SITE_SOURCE_REF: website,
    SITE_STAGED_SOURCE_REF: sha });
  assert.deepEqual([production.sourceRef, production.releaseRef,
    production.staging], [website, sha, false]);
  assert.equal(releaseDestination({ SITE_SOURCE_REF: sha }).releaseRef, sha);
  assert.throws(() => releaseDestination({ SITE_SOURCE_REF: website,
    SITE_STAGED_SOURCE_REF: "feature" }));
  assert.throws(() => releaseDestination({ SITE_SOURCE_REF: website,
    SITE_STAGED_SOURCE_REF: "main", SITE_RELEASE_CHANNEL: "staging",
    SITE_CANDIDATE_ID: candidate }));
});
