import assert from "node:assert/strict";
import test from "node:test";

import config from "../astro.config.mjs";

test("styles x2c in Markdown prose but not code", async () => {
  const renderer = await config.markdown.processor.createRenderer({
    syntaxHighlight: false
  });
  const { code } = await renderer.render("x2c in prose and `x2c` in code");

  assert.equal(
    code,
    '<p><span class="x2c-wordmark">x2c</span> in prose and ' +
      "<code>x2c</code> in code</p>\n"
  );
});

test("proxies the live book through the Astro development server", async () => {
  const origin = "http://127.0.0.1:43199";
  process.env.X2C_DOCS_DEV_ORIGIN = origin;

  let devConfig;
  try {
    ({ default: devConfig } = await import(
      "../astro.config.mjs?docs-proxy"
    ));
  } finally {
    delete process.env.X2C_DOCS_DEV_ORIGIN;
  }

  const proxy = devConfig.vite.server.proxy;
  assert.equal(proxy["/docs"].target, origin);
  assert.equal(
    proxy["/docs"].rewrite("/docs/guide/from-c.html"),
    "/guide/from-c.html"
  );
  assert.equal(proxy["/__livereload"].target, origin);
  assert.equal(proxy["/__livereload"].ws, true);
});
