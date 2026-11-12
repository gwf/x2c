import type { MarkdownInstance } from "astro";

type ExampleMarkdown = MarkdownInstance<Record<string, any>>;

const files = import.meta.glob<ExampleMarkdown>("../content/slides/*.md", {
  eager: true,
});

// Filename order controls presentation; frontmatter slugs keep links stable.
export const slides = Object.keys(files).sort().map((path) => files[path]);
export const inSection = (name: string) =>
  slides.filter((slide) => slide.frontmatter.section === name && slide.frontmatter.home !== false)
    .sort((a, b) => (a.frontmatter.order ?? 0) - (b.frontmatter.order ?? 0));

export const articles = Object.values(
  import.meta.glob<ExampleMarkdown>("../content/examples/*.md", { eager: true }),
).sort((a, b) => a.frontmatter.order - b.frontmatter.order);
export const articleFor = (slug: string) =>
  articles.find((article) =>
    !article.frontmatter.customPage && article.frontmatter.slide === slug);

// Complete examples run their published WebAssembly programs.
import gallery from "../../../examples/gallery.json";
import {
  selectPlaygroundExamples,
} from "../../scripts/playground-examples.mjs";
const sources = import.meta.glob("../../../examples/{love,magic,power}/*.x", {
  query: "?raw", import: "default", eager: true,
});
const built = Object.values(import.meta.glob(
  "../../../builds/wasm/playground/programs.json",
  { import: "default", eager: true },
))[0] as string[] | undefined;
const programs = new Set(import.meta.env.PROD ? built ?? [] : []);

const sourceFor = (id: string) =>
  sources[`../../../examples/${id}.x`] as string | undefined;
export const playgroundExamples = selectPlaygroundExamples(gallery, sourceFor)
  .filter((entry) => programs.has(entry.id))
  .map(({ id, source }) => ({ id, source, program: programs.has(id) }));
