import { pathToFileURL } from "node:url";
import path from "node:path";

import { createHighlighter } from "shiki";
import { markdownToMdast } from "satteri";

import {
  x2cDarkTheme,
  x2cLang,
  x2cLightTheme,
  x2cLispLang
} from "../shiki-x2c.mjs";
import { wordmarkHtml, wordmarkParts } from "../wordmark.mjs";

let highlighterPromise;

function highlighter() {
  highlighterPromise ??= createHighlighter({
    themes: [x2cDarkTheme, x2cLightTheme],
    langs: [x2cLang, x2cLispLang]
  });
  return highlighterPromise;
}

function replacementNodes(node, result = [], parent = null) {
  const linkText = node.type === "text" && parent?.type === "link" &&
    parent.children.length === 1;
  const bareUrl = linkText &&
    node.position.start.offset === parent.position.start.offset &&
    node.position.end.offset === parent.position.end.offset;
  const angleUrl = linkText &&
    node.position.start.offset === parent.position.start.offset + 1 &&
    node.position.end.offset === parent.position.end.offset - 1;
  const urlText = bareUrl || angleUrl;
  if (node.type === "code" || (node.type === "text" && !urlText)) {
    result.push(node);
  }
  for (const child of node.children ?? []) {
    replacementNodes(child, result, node);
  }
  return result;
}

function renderWordmarks(source) {
  const parts = wordmarkParts(source);
  if (parts.length === 1) return null;
  return parts.map((part) => part === "x2c" ? wordmarkHtml : part).join("");
}

function codeInfo(node) {
  const [sourceLanguage, ...commaFlags] = (node.lang ?? "").split(",");
  const language = sourceLanguage === "xlisp"
    ? "x2c-lisp"
    : sourceLanguage;

  if (language !== "x2c" && language !== "x2c-lisp") return null;

  const metaFlags = (node.meta ?? "").split(/[\s,]+/);
  const flags = [...commaFlags, ...metaFlags]
    .filter((flag) => /^[a-zA-Z0-9_-]+$/.test(flag));

  return { sourceLanguage, language, flags };
}

function visibleCode(source, hideLines) {
  const hidden = new Set();
  if (!hideLines) return { code: source, hidden };

  const code = source.split("\n").map((line, index) => {
    const match = line.match(/^(\s*)~(.*)$/);
    if (!match) return line;
    hidden.add(index + 1);
    return match[1] + match[2];
  }).join("\n");

  return { code, hidden };
}

async function renderCode(node) {
  const info = codeInfo(node);
  if (!info) return null;

  const { code, hidden } = visibleCode(
    node.value,
    info.sourceLanguage === "x2c"
  );
  const instance = await highlighter();

  const html = instance.codeToHtml(code, {
    lang: info.language,
    themes: {
      light: x2cLightTheme.name,
      dark: x2cDarkTheme.name
    },
    defaultColor: false,
    transformers: [{
      name: "x2c-mdbook",
      pre(element) {
        this.addClassToHast(element, "x2c-code");
      },
      code(element) {
        this.addClassToHast(element, [
          `language-${info.sourceLanguage}`,
          "no-highlight",
          ...info.flags
        ]);
      },
      line(element, line) {
        if (hidden.has(line)) this.addClassToHast(element, "boring");
      }
    }]
  });

  return html
    .replaceAll(
      '</span>\n<span class="line',
      '&#10;</span><span class="line'
    )
    .replaceAll("\n", "&#10;");
}

export async function highlightMarkdown(markdown) {
  const replacements = [];
  const codeUnits = [0];
  let codeUnit = 0;

  for (const character of markdown) {
    codeUnit += character.length;
    codeUnits.push(codeUnit);
  }

  for (const node of replacementNodes(markdownToMdast(markdown))) {
    const start = codeUnits[node.position.start.offset];
    const end = codeUnits[node.position.end.offset];
    const html = node.type === "code"
      ? await renderCode(node)
      : renderWordmarks(markdown.slice(start, end));
    if (html === null) continue;
    replacements.push({
      start,
      end,
      html
    });
  }

  replacements.sort((left, right) => right.start - left.start);
  for (const replacement of replacements) {
    markdown = markdown.slice(0, replacement.start) + replacement.html +
      markdown.slice(replacement.end);
  }

  return markdown;
}

async function highlightItems(items) {
  for (const item of items) {
    const chapter = item.Chapter;
    if (!chapter) continue;
    chapter.content = await highlightMarkdown(chapter.content);
    await highlightItems(chapter.sub_items);
  }
}

export async function highlightBook(book) {
  await highlightItems(book.items);
  return book;
}

export function supportsRenderer(renderer) {
  return renderer === "html";
}

async function readStdin() {
  let input = "";
  process.stdin.setEncoding("utf8");
  for await (const chunk of process.stdin) input += chunk;
  return input;
}

async function main() {
  if (process.argv[2] === "supports") {
    process.exitCode = supportsRenderer(process.argv[3]) ? 0 : 1;
    return;
  }

  const [, book] = JSON.parse(await readStdin());
  process.stdout.write(JSON.stringify(await highlightBook(book)));
}

const invokedPath = process.argv[1]
  ? pathToFileURL(path.resolve(process.argv[1])).href
  : null;

if (invokedPath === import.meta.url) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
