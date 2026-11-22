// Use the installed mdBook implementation that also builds Docs.
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import brand from "../docs/theme/x2c.css?raw";
import template from "../docs/theme/index.hbs?raw";
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
    const general = readFileSync(join(dir, "theme/css/general.css"), "utf8");
    const chrome = readFileSync(join(dir, "theme/css/chrome.css"), "utf8");
    const tocFile = readdirSync(join(dir, "book")).find(file => /^toc-.*\.js$/.test(file));
    const toc = readFileSync(join(dir, "book", tocFile), "utf8");
    const colors = [...brand.matchAll(/--sidebar-(?:bg|fg|non-existant|active|spacer):[^;]+;/g)].slice(0, 5).map(match => match[0]).join("\n");
    assets = {
      init: between(template, "/* Sidebar bootstrap */", "/* End sidebar bootstrap */"),
      script: between(theme, "(function sidebar()", "(function chapterNavigation()") +
        "\n(() => {\n" + between(toc, "        // Toggle buttons", "    }\n}") + "\n})();" +
        between(template, "/* Sidebar interactions */", "/* End sidebar interactions */"),
      tracking: between(toc, "(function() {", "    // Takes the nodes from the given head") + `
    document.addEventListener('DOMContentLoaded', () => {
        const group = document.querySelector('[data-track-example-sections]');
        if (!group) return;
        headers = [];
        for (const link of group.querySelectorAll('[data-index-link]')) {
            const hash = new URL(link.href).hash;
            const section = document.getElementById(hash.slice(1));
            if (!section) continue;
            headers.push(section);
            link.href = hash;
            link.classList.add('header-in-summary');
            link.addEventListener('click', headerThresholdClick);
        }
        reloadCurrentHeader();
    });
    document.addEventListener('scroll', reloadCurrentHeader, { passive: true });
})();`,
      css: between(general, ".page-wrapper {", ".content {") +
        between(chrome, ".sidebar {", "/* Theme Menu Popup */") +
        between(brand, "/* Sidebar */", "/* Footer pager */") +
        `\n:is(.examples-shell, .about-shell) { --x2c-red-text: var(--red-text); ${colors} }`,
    };
    return assets;
  } finally { rmSync(dir, {recursive: true, force: true}); }
}
