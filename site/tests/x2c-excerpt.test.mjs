import assert from "node:assert/strict";
import test from "node:test";
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
