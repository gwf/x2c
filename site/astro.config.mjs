import { defineConfig } from "astro/config";
import { satteri } from "@astrojs/markdown-satteri";
import { fileURLToPath } from "node:url";

import { siteBase, siteUrl } from "./site-config.mjs";
import {
  x2cDarkTheme,
  x2cLang,
  x2cLispLang
} from "./shiki-x2c.mjs";
import { wordmark } from "./wordmark.mjs";

// docs/book.toml hides "~" lines from the reader while
// tools/check-doc-examples.py still compiles them. Markdown pages moved from
// the book carry those lines, so drop them here for the same reason. No
// hand-written C on this site starts a line with "~".
const hiddenLines = {
  name: "x2c-hidden-lines",
  preprocess(code) {
    if (this.options.lang !== "x2c") return code;
    return code
      .split("\n")
      .filter((line) => !line.trimStart().startsWith("~"))
      .join("\n")
      .trim();
  }
};

const docsDevOrigin = process.env.X2C_DOCS_DEV_ORIGIN;
const docsDevPath = "/docs";
const docsDevProxy = docsDevOrigin
  ? {
      [docsDevPath]: {
        target: docsDevOrigin,
        changeOrigin: true,
        ws: true,
        rewrite: (pathname) => pathname.slice(docsDevPath.length) || "/"
      },
      "/__livereload": {
        target: docsDevOrigin,
        changeOrigin: true,
        ws: true
      }
    }
  : undefined;

export default defineConfig({
  site: siteUrl,
  base: siteBase,
  output: "static",
  trailingSlash: "always",
  build: {
    assets: "assets"
  },
  vite: {
    define: {
      "import.meta.env.X2C_REPOSITORY_ROOT": JSON.stringify(
        fileURLToPath(new URL("..", import.meta.url))
      )
    },
    server: {
      proxy: docsDevProxy,
      watch: {
        usePolling: true,
        interval: 100
      }
    }
  },
  markdown: {
    processor: satteri({ mdastPlugins: [wordmark] }),
    shikiConfig: {
      theme: x2cDarkTheme,
      langs: [x2cLang, x2cLispLang],
      langAlias: { xlisp: "x2c-lisp", "x2c,ignore": "x2c" },
      transformers: [hiddenLines]
    }
  }
});
