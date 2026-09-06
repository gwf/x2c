import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import test from "node:test";

import { createHighlighter } from "shiki";

import { x2cDarkTheme, x2cLang } from "../shiki-x2c.mjs";

const slides = new URL("../src/content/slides/", import.meta.url);

function sourceCode(name) {
  const markdown = readFileSync(new URL(name, slides), "utf8");
  return markdown.match(/```x2c\n([\s\S]*?)\n```/)?.[1];
}

test("uses the distinct x2c style throughout the landing galleries", async () => {
  const highlighter = await createHighlighter({
    themes: [x2cDarkTheme],
    langs: [x2cLang]
  });
  const seen = new Set();

  const names = readdirSync(slides).filter((file) => file.endsWith(".md"));
  for (const name of names) {
    const code = sourceCode(name);
    if (!code) continue;
    const result = highlighter.codeToTokens(code, {
      lang: "x2c",
      theme: x2cDarkTheme.name
    });

    for (const [line, source] of code.split("\n").entries()) {
      const statement = source.match(/^\s*(foreach|match|raise|catch)\b/);
      const spelling = statement?.[1] ??
        (!source.trimStart().startsWith("//") && source.includes("=>")
          ? "=>"
          : null);
      if (!spelling) continue;

      seen.add(spelling);
      const token = result.tokens[line].find(({ content }) =>
        content.includes(spelling)
      );
      const message = `${name}:${line + 1}: ${source}`;
      assert.equal(token?.color, "#FF4FD8", message);
      assert.equal(token?.fontStyle, 2, message);
    }
  }

  assert.deepEqual(
    [...seen].sort(),
    ["=>", "catch", "foreach", "match", "raise"]
  );
});
