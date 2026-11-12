import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { x2cExcerpt } from "../x2c-excerpt.mjs";

test("a hidden main loses only its wrapper indentation, not nested indentation", () => {
  const source = ["int helper(void) {", "  return 42;", "}", "", "~int main(void) {", "  int n = helper();", "  if (n) {", "    puts(\"yes\");", "  }", "~  return 0;", "~}"].join("\n");
  assert.equal(x2cExcerpt(source), ["int helper(void) {", "  return 42;", "}", "", "int n = helper();", "if (n) {", "  puts(\"yes\");", "}"].join("\n"));
});

test("visible main and already unindented excerpts keep their indentation", () => {
  const full = "int main(void) {\n  if (1) {\n    puts(\"yes\");\n  }\n}";
  assert.equal(x2cExcerpt(full), full);
  assert.equal(x2cExcerpt("~int main(void) {\nif (1)\n  puts(\"yes\");\n~}"), "if (1)\n  puts(\"yes\");");
});

// Enforce the presentation contract across the corpus, not selected slides.
test("every home gallery shows an excerpt without program scaffolding", () => {
  const entries = JSON.parse(readFileSync(new URL("../../examples/gallery.json", import.meta.url)));
  let count = 0;
  for (const entry of entries) {
    const markdown = readFileSync(new URL(`../src/content/slides/${entry.slide}`, import.meta.url), "utf8");
    if (/^home: false$/m.test(markdown)) continue;
    const block = markdown.match(/```x2c(?:,ignore)?\n([\s\S]*?)\n```/);
    assert.ok(block, entry.slide);
    const excerpt = x2cExcerpt(block[1]);
    assert.doesNotMatch(excerpt, /^#include|\bint main\(|\b(?:argc|argv|example_data)\b/m, entry.slide);
    assert.ok(excerpt.trim(), entry.slide);
    count++;
  }
  assert.ok(count > 0, "home galleries must not be empty");
});
