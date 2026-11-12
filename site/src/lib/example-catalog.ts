import type { MarkdownInstance } from "astro";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import gallery from "../../../examples/gallery.json";
import { slides, articles, playgroundExamples } from "./examples";
import { selectPlaygroundExamples } from "../../scripts/playground-examples.mjs";

type ExampleMarkdown = MarkdownInstance<Record<string, any>>;
const published = new Map(playgroundExamples.map(entry => [entry.id, entry]));
const read = (path: string) =>
  readFileSync(join(import.meta.env.X2C_REPOSITORY_ROOT, path), "utf8");

const runnable = new Set(selectPlaygroundExamples(gallery,
  (id: string) => read(`examples/${id}.x`)).map(entry => entry.id));

// The manifest names each example's expected stdout relative to examples/.
const expected = new Map(read("examples/manifest.txt").split("\n")
  .filter((line) => line && !line.startsWith("#"))
  .map((line) => line.split("|"))
  .filter((row) => row[4] && row[4] !== "-")
  .map((row) => [`examples/${row[0]}.x`, `examples/${row[4]}`]));
const outputFor = (path: string, fallback?: string) => {
  const file = expected.get(path) ?? fallback;
  return file ? read(file) : undefined;
};

const galleryEntries = gallery.flatMap((entry) => {
  if (entry.language) return [];
  const path = entry.example ? `examples/${entry.example}.x` : entry.source;
  if (!path?.startsWith("examples/") || !path.endsWith(".x")) return [];
  const id = path.slice("examples/".length, -2);
  const flagFile = path.slice(0, -2) + ".flags";
  const flags = existsSync(join(import.meta.env.X2C_REPOSITORY_ROOT, flagFile))
    ? read(flagFile).trim() : "";
  const source = read(path);
  const slide = slides.find((item) => item.file?.endsWith(`/${entry.slide}`))!;
  return [{
    id, section: slide.frontmatter.section, path, source,
    label: slide.frontmatter.tab
      ?? id.split("/").pop()!.replaceAll("-", " "),
    runnable: runnable.has(id),
    visible: source, program: published.get(id)?.program ?? false,
    recipe: `x2c run ${flags ? flags + " " : ""}${path}`,
    output: outputFor(path), slide,
  }];
});

const recipes: Record<string, string> = {
  notes: "make -C examples/apps/notes prepare\nmake -C examples/apps/notes run",
  "literate-lisp": "./x2c run examples/programs/literate-lisp.x -- " +
    "examples/data/reference-lisp/showcase.xlisp",
};
const programEntries = articles.map((article) => {
  const page = article.frontmatter;
  const source = read(page.source);
  return {
    id: `programs/${page.slug}`, section: "programs", path: page.source,
    source, visible: source,
    label: page.navTitle, runnable: false, program: false,
    output: outputFor(page.source, page.output), article,
    recipe: (page.run ?? recipes[page.slug]).trim(),
  };
});

// Every program on the examples page, in list order.
export const exampleEntries: {
  id: string; section: string; path: string; source: string; label: string;
  runnable: boolean; visible: string; program: boolean; output?: string; slide?: ExampleMarkdown;
  article?: ExampleMarkdown; recipe?: string; description?: string;
}[] = [...galleryEntries, ...programEntries];
export const exampleSections = ["love", "power", "magic", "programs"];

