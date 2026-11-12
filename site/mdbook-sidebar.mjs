// Use the installed mdBook implementation that also builds Docs.
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import brand from "../docs/theme/x2c.css?raw";
let assets;
function between(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  if (a < 0 || b < 0) throw new Error(`Unsupported mdBook theme: ${start}`);
  return source.slice(a, b);
}
export function mdbookSidebarAssets() {
  if (assets) return assets;
  const dir = mkdtempSync(join(tmpdir(), "x2c-sidebar-"));
  try {
    const mdbook = process.env.MDBOOK_BIN || "mdbook";
    execFileSync(mdbook, ["init", "--theme", "--force", "--ignore", "none", dir], {stdio: "pipe"});
    execFileSync(mdbook, ["build", dir], {stdio: "pipe"});
    const theme = readFileSync(join(dir, "theme/book.js"), "utf8");
    const chrome = readFileSync(join(dir, "theme/css/chrome.css"), "utf8");
    const tocFile = readdirSync(join(dir, "book")).find(file => /^toc-.*\.js$/.test(file));
    const toc = readFileSync(join(dir, "book", tocFile), "utf8");
    const colors = [...brand.matchAll(/--sidebar-(?:bg|fg|non-existant|active|spacer):[^;]+;/g)].slice(0, 5).map(match => match[0]).join("\n");
    assets = {
      script: between(theme, "(function sidebar()", "(function chapterNavigation()") +
        "\n(() => {\n" + between(toc, "        // Toggle buttons", "    }\n}") + "\n})();",
      css: between(chrome, ".sidebar {", ".on-this-page {") +
        between(brand, "/* Sidebar */", "/* Footer pager */") +
        "\nhtml:has(.examples-shell) .sidebar, .examples-shell .chapter-fold-toggle div { transition: none !important; }" +
        `\n.examples-shell { --x2c-red-text: var(--red-text); ${colors} }`,
    };
    return assets;
  } finally { rmSync(dir, {recursive: true, force: true}); }
}
