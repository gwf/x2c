import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import test from "node:test";

const script = fileURLToPath(
  new URL("../scripts/highlight-book.mjs", import.meta.url)
);

const x2cMarkdown = [
  "😀 before the fence",
  "",
  "```x2c,ignore",
  "~Array hidden = %[1, 2, 3];",
  "macro Statement $show(Expr $value) using $temporary => {",
  "  List shown = %($value);",
  "}",
  "```",
  "",
  "```text",
  "foreach remains plain text",
  "```",
  "",
  '<pre><code class="language-x2c">raw stays raw</code></pre>'
].join("\n");

const lispMarkdown = [
  "```xlisp",
  "~literal",
  "```",
  "",
  "```x2c-lisp",
  "(list value)",
  "```"
].join("\n");

const wordmarkMarkdown = [
  "# From C to x2c",
  "",
  "😀 x2c in prose, [x2c](https://example.com/x2c), [x2c](x2c), and `x2c`.",
  "AT&amp;T uses x2c.",
  "https://x2c.dev, <https://x2c.dev>, and x2c@example.com stay links.",
  "",
  "```text",
  "x2c in fenced code",
  "```",
  "",
  '<span data-name="x2c">x2c between inline HTML tags</span>',
  "",
  "<div>x2c in a raw HTML block</div>"
].join("\n");

function run(args = [], input = "") {
  return spawnSync(process.execPath, [script, ...args], {
    encoding: "utf8",
    input
  });
}

test("highlights mdBook x2c fences with the extension grammar", () => {
  const book = {
    items: [{
      Chapter: {
        content: x2cMarkdown,
        sub_items: [{
          Chapter: {
            content: lispMarkdown,
            sub_items: []
          }
        }]
      }
    }]
  };
  const result = run([], JSON.stringify([{}, book]));

  assert.equal(result.status, 0, result.stderr);
  const highlightedBook = JSON.parse(result.stdout);
  const chapter = highlightedBook.items[0].Chapter;
  const highlighted = chapter.content;

  assert.match(highlighted, /^😀 before the fence/);
  assert.match(
    highlighted,
    /<code class="language-x2c no-highlight ignore">/
  );
  assert.match(
    highlighted,
    /class="line boring">.*&#10;<\/span><span class="line">/
  );
  assert.doesNotMatch(highlighted, /~Array hidden/);
  assert.match(
    highlighted,
    /--shiki-light:#A626A4;--shiki-light-font-weight:bold;/
  );
  assert.match(
    highlighted,
    /--shiki-dark:#FF4FD8;--shiki-dark-font-weight:bold[">]/
  );
  assert.match(highlighted, /--shiki-light:#007C8A;--shiki-dark:#29D3E2/);
  assert.match(
    highlighted,
    /--shiki-light:#A15C00;--shiki-light-font-style:italic;/
  );
  assert.match(
    highlighted,
    /--shiki-dark:#FFB454;--shiki-dark-font-style:italic[">]/
  );
  assert.match(highlighted, /> %\[<\/span>/);
  assert.match(highlighted, /> %\(\$<\/span>/);
  assert.match(
    highlighted,
    /```text\nforeach remains plain text\n```/
  );
  assert.match(
    highlighted,
    /<pre><code class="language-x2c">raw stays raw<\/code><\/pre>$/
  );

  const nested = chapter.sub_items[0].Chapter.content;
  assert.match(nested, /class="language-xlisp no-highlight"/);
  assert.match(nested, /class="language-x2c-lisp no-highlight"/);
  assert.match(nested, />~literal<\/span>/);
  assert.doesNotMatch(nested, /class="line boring"/);
});

test("supports only mdBook's HTML renderer", () => {
  const html = run(["supports", "html"]);
  assert.equal(html.status, 0, html.stderr);

  const markdown = run(["supports", "markdown"]);
  assert.equal(markdown.status, 1, markdown.stderr);
});

test("word-marks mdBook prose but not technical text", () => {
  const book = {
    items: [{
      Chapter: {
        content: wordmarkMarkdown,
        sub_items: []
      }
    }]
  };
  const result = run([], JSON.stringify([{}, book]));

  assert.equal(result.status, 0, result.stderr);
  const transformed = JSON.parse(result.stdout).items[0].Chapter.content;
  const mark = '<span class="x2c-wordmark">x2c</span>';
  const links =
    "https://x2c.dev, <https://x2c.dev>, and x2c@example.com stay links.";

  assert.match(transformed, new RegExp(`^# From C to ${mark}`));
  assert.match(transformed, new RegExp(`😀 ${mark} in prose`));
  assert.match(
    transformed,
    new RegExp(`\\[${mark}\\]\\(https://example\\.com/x2c\\)`)
  );
  assert.match(transformed, new RegExp(`\\[${mark}\\]\\(x2c\\)`));
  assert.match(transformed, /and `x2c`\./);
  assert.match(transformed, new RegExp(`AT&amp;T uses ${mark}\\.`));
  assert.ok(transformed.includes(links));
  assert.match(transformed, /```text\nx2c in fenced code\n```/);
  assert.match(
    transformed,
    new RegExp(
      `<span data-name="x2c">${mark} between inline HTML tags<\\/span>`
    )
  );
  assert.match(transformed, /<div>x2c in a raw HTML block<\/div>$/);
});
