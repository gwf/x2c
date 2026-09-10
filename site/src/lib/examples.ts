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
);
export const articleFor = (slug: string) =>
  articles.find((article) => article.frontmatter.slide === slug);
