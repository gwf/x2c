import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import test from "node:test";

import { createHighlighter } from "shiki";
import { createSatteriMarkdownProcessor } from "@astrojs/markdown-satteri";

import config from "../astro.config.mjs";
import { x2cDarkTheme, x2cLightTheme, x2cLang } from "../shiki-x2c.mjs";

const slides = new URL("../src/content/slides/", import.meta.url);

test("hides marked setup lines in both site x2c fence spellings", async () => {
  const processor = await createSatteriMarkdownProcessor({
    shikiConfig: config.markdown.shikiConfig
  });
  for (const lang of ["x2c", "x2c,ignore"]) {
    const { code } = await processor.render([
      `\`\`\`${lang}`,
      "~#include <math.h>",
      "  ~int hidden = 1;",
      "int flipped = ~bits;",
      "\`\`\`"
    ].join("\n"));
    assert.doesNotMatch(code, /#include|hidden/);
    assert.match(code, /flipped = ~bits;/);
  }
  const { code } = await processor.render("```text\n~literal\n```");
  assert.match(code, /~literal/);
});

test("recognizes quotation sigils and kinds in the shared grammar", async () => {
  const highlighter = await createHighlighter({
    themes: [x2cDarkTheme],
    langs: [x2cLang]
  });
  for (const body of ["Type{ int * }", "Param{ int $name }",
    "Unit{ int $name; }", "int{ $value }", "(int){ $value }",
    "( $value + 1 )", "{ return $value; }"]) {
    const result = highlighter.codeToTokens(`List code = $!${body};`, {
      lang: "x2c", theme: x2cDarkTheme.name, includeExplanation: true
    });
    const parts = result.tokens[0].flatMap((token) => token.explanation);
    assert.ok(parts.some((part) => part.content === "$!" &&
      part.scopes.some(({ scopeName }) =>
        scopeName === "punctuation.definition.macro.sigil.x2c")), body);
    const kind = body.match(/^(Type|Param|Unit)\b/)?.[1];
    if (kind) assert.ok(parts.some((part) => part.content === kind &&
      part.scopes.some(({ scopeName }) =>
        scopeName === "storage.type.macro.result.x2c")), body);
  }
  highlighter.dispose();
});

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


test("site and book themes match approved semantic type, modifier, and sigil styling", async () => {
  const highlighter = await createHighlighter({
    themes: [x2cDarkTheme, x2cLightTheme], langs: [x2cLang]
  });
  try {
    for (const [theme, keyword, type] of [
      [x2cDarkTheme, "#FF4FD8", "#29D3E2"],
      [x2cLightTheme, "#A626A4", "#007C8A"]
    ]) {
      for (const code of [
        "meta native static Code build(Code value);",
        "Macro value = $!Stmt{ return $value; };",
        "TypeInfo info; Source source; Name name;",
        "consume($);", "Var value = %( ${code} );"
      ]) {
        const { tokens } = highlighter.codeToTokens(code, {
          lang: "x2c", theme: theme.name, includeExplanation: true
        });
        for (const token of tokens[0]) {
          const scopes = token.explanation.flatMap(part =>
            part.scopes.map(({ scopeName }) => scopeName));
          if (scopes.some(scope => [
            "storage.modifier.meta.x2c", "storage.modifier.native.x2c",
            "punctuation.definition.macro.sigil.x2c"
          ].includes(scope) || scope.startsWith("punctuation.definition.interpolation"))) {
            assert.equal(token.color, keyword, `${theme.name}: ${token.content}`);
            assert.equal(token.fontStyle, 2, `${theme.name}: ${token.content}`);
          }
          if (scopes.includes("support.type.prelude.x2c"))
            assert.equal(token.color, type, `${theme.name}: ${token.content}`);
        }
      }
    }
  } finally {
    highlighter.dispose();
  }
});
