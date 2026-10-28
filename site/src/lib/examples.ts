import type { MarkdownInstance } from "astro";

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

// Only self-contained gallery programs with browser runtime support.
import gallery from "../../../examples/gallery.json";
const sources = import.meta.glob("../../../examples/{love,magic,power}/*.x", {
  query: "?raw", import: "default", eager: true,
});
export const playgroundExamples = gallery.flatMap((entry) => {
  if (!entry.example || entry.optional || entry.language) return [];
  const source = sources[`../../../examples/${entry.example}.x`] as string;
  if (/^(love\/files|power\/counting)$/.test(entry.example)) return [];
  if (!source || /\b(Thread|Channel|Dispatch|Job)\b|Pool\.start|File\.popen/.test(source))
    return [];
  const slide = slides.find((item) => item.file?.endsWith(`/${entry.slide}`));
  return [{ id: entry.example, source,
    slug: slide?.frontmatter.slug,
    label: entry.example.replaceAll("/", " / ") }];
});
export const playgroundFor = (slug: string) =>
  playgroundExamples.find((entry) => entry.slug === slug);
