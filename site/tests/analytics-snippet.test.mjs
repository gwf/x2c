import assert from "node:assert/strict";
import test from "node:test";
import vm from "node:vm";
import { analyticsSnippet } from "../analytics-snippet.mjs";

const configured = {
  SITE_ANALYTICS: "production",
  PLAUSIBLE_SCRIPT_URL: "https://plausible.io/js/pa-example.js",
};

test("measurement requires production opt-in and a configured script", () => {
  assert.equal(analyticsSnippet({}), "");
  assert.equal(analyticsSnippet({ SITE_ANALYTICS: "production" }), "");
  assert.equal(analyticsSnippet({
    PLAUSIBLE_SCRIPT_URL: configured.PLAUSIBLE_SCRIPT_URL,
  }), "");
  assert.equal(analyticsSnippet(configured, true), "");
});

test("official loader configures one pageview owner and no automatic actions", () => {
  const snippet = analyticsSnippet(configured);
  assert.equal((snippet.match(/<script async src=/g) || []).length, 1);
  assert.ok(snippet.includes(configured.PLAUSIBLE_SCRIPT_URL));
  const context = vm.createContext({});
  context.window = context;
  vm.runInContext(snippet.match(/<script>([\s\S]*?)<\/script>/)[1], context);
  assert.equal(context.plausible.o.outboundLinks, false);
  assert.equal(context.plausible.o.fileDownloads, false);
  assert.equal(context.plausible.o.formSubmissions, false);
  assert.equal(context.plausible.o.autoCapturePageviews, undefined);
  assert.equal(context.plausible.q, undefined);
});

test("the configured URL remains a single HTML attribute", () => {
  const snippet = analyticsSnippet({
    ...configured,
    PLAUSIBLE_SCRIPT_URL: 'https://plausible.io/js/pa-example.js?a="b"&c=<d>',
  });
  assert.ok(snippet.includes('?a=&quot;b&quot;&amp;c=&lt;d&gt;"'));
});
