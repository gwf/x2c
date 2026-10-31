const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

test("current collection and expression delimiters are bracket pairs", () => {
  const source = fs.readFileSync(
    path.join(__dirname, "..", "language-configuration.json"), "utf8"
  );
  const configuration = JSON.parse(JSON.stringify(vm.runInNewContext(`(${source})`)));
  for (const pair of [["${", "}"], ["$(", ")"], ["@(", ")"], ["%<", ">"]])
    assert.ok(configuration.brackets.some(([open, close]) => open === pair[0] && close === pair[1]));
  assert.ok(!configuration.brackets.some(([open]) => open === "@{"));
  assert.ok(configuration.autoClosingPairs.some(([open, close]) => open === "%<" && close === ">"));
});
