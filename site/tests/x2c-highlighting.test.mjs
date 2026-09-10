import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import test from "node:test";

import { createHighlighter } from "shiki";

import { x2cDarkTheme, x2cLang } from "../shiki-x2c.mjs";

const slides = new URL("../src/content/slides/", import.meta.url);

function sourceCode(name) {
  const markdown = readFileSync(new URL(name, slides), "utf8");
  return markdown.match(/```x2c(?:,ignore)?\n([\s\S]*?)\n```/)?.[1];
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
      theme: x2cDarkTheme.name,
      includeExplanation: true
    });

    for (const [line, tokens] of result.tokens.entries()) {
      for (const token of tokens) {
        const spellings = new Set(token.explanation?.flatMap((part) =>
          part.scopes.flatMap(({ scopeName }) => {
            const keyword = scopeName.match(
              /^keyword\.control\.(foreach|match|raise|catch)\.x2c$/
            );
            if (keyword) return [keyword[1]];
            return scopeName === "keyword.operator.arrow.x2c" ? ["=>"] : [];
          })
        ));
        if (token.content.includes("=>") && !token.explanation?.some((part) =>
          part.scopes.some(({ scopeName }) => /^(string|comment)\./.test(scopeName))
        )) spellings.add("=>");
        for (const spelling of spellings) {
          seen.add(spelling);
          const message = `${name}:${line + 1}: ${token.content}`;
          assert.equal(token.color, "#FF4FD8", message);
          assert.equal(token.fontStyle, 2, message);
        }
      }
    }
  }

  assert.deepEqual(
    [...seen].sort(),
    ["=>", "catch", "foreach", "match", "raise"]
  );
});
