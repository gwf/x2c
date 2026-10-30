import type { MarkdownInstance } from "astro";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import gallery from "../../../examples/gallery.json";

type ExampleMarkdown = MarkdownInstance<Record<string, any>>;

const files = import.meta.glob<ExampleMarkdown>("../content/slides/*.md", {
  eager: true,
});

// Filename order controls presentation; frontmatter slugs keep links stable.
export const slides = Object.keys(files).sort().map((path) => files[path]);
export const inSection = (name: string) =>
  slides.filter((slide) => slide.frontmatter.section === name);

export const articles = Object.values(
  import.meta.glob<ExampleMarkdown>("../content/examples/*.md", { eager: true }),
).sort((a, b) => a.frontmatter.order - b.frontmatter.order);
export const articleFor = (slug: string) =>
  articles.find((article) =>
    !article.frontmatter.customPage && article.frontmatter.slide === slug);

const read = (path: string) =>
  readFileSync(join(import.meta.env.X2C_REPOSITORY_ROOT, path), "utf8");

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

// The browser runtime has no threads, processes, or input files.
const browserSafe = (id: string, source: string) =>
  !/^(love\/files|power\/counting)$/.test(id) &&
  !/\b(Thread|Channel|Dispatch|Job)\b|Pool\.start|File\.popen/.test(source);

const galleryEntries = gallery.flatMap((entry) => {
  if (!entry.example || entry.language) return [];
  const path = `examples/${entry.example}.x`;
  const source = read(path);
  const slide = slides.find((item) => item.file?.endsWith(`/${entry.slide}`))!;
  return [{
    id: entry.example, section: entry.example.split("/")[0], path, source,
    label: slide.frontmatter.tab
      ?? entry.example.split("/").pop()!.replaceAll("-", " "),
    runnable: !entry.optional && browserSafe(entry.example, source),
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
  return {
    id: `programs/${page.slug}`, section: "programs", path: page.source,
    source: read(page.source), label: page.navTitle, runnable: false,
    output: outputFor(page.source, page.output), article,
    recipe: (page.run ?? recipes[page.slug]).trim(),
  };
});

const tours = [
  { name: "language", label: "Language tour",
    description: "A fifteen-minute tour of the language in one program you can run." },
  { name: "hello-worlds", label: "Hello, worlds",
    description: "Twelve idiomatic ways to say Hello, World, from Lists and Maps to runtime Lisp and macros." },
];
const tourEntries = tours.map(({ name, label, description }) => {
  const path = `examples/tours/${name}.x`;
  const source = read(path);
  return {
    id: `tours/${name}`, section: "programs", path, source, label,
    runnable: browserSafe(`tours/${name}`, source), output: outputFor(path),
    description,
  };
});

// Every program on the examples page, in list order.
export const exampleEntries: {
  id: string; section: string; path: string; source: string; label: string;
  runnable: boolean; output?: string; slide?: ExampleMarkdown;
  article?: ExampleMarkdown; recipe?: string; description?: string;
}[] = [...galleryEntries, ...programEntries, ...tourEntries];
export const exampleSections = ["love", "power", "magic", "programs"];

// Only self-contained gallery programs with browser runtime support.
export const playgroundExamples = galleryEntries
  .filter((entry) => entry.runnable)
  .map((entry) => ({ id: entry.id, source: entry.source,
    slug: entry.slide.frontmatter.slug,
    label: entry.id.replaceAll("/", " / ") }));
export const playgroundFor = (slug: string) =>
  playgroundExamples.find((entry) => entry.slug === slug);
