const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

test("runtime interpolation delimiters are bracket pairs", () => {
  const source = fs.readFileSync(
    path.join(__dirname, "..", "language-configuration.json"),
    "utf8"
  );
  const configuration = vm.runInNewContext(`(${source})`);

  assert.deepEqual(
    JSON.parse(JSON.stringify(configuration.brackets.slice(0, 2))),
    [["${", "}"], ["@{", "}"]]
  );
});
