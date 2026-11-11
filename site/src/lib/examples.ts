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

// Gallery programs the playground can run in the browser. Without a compile
// service, only examples with precompiled programs can run, and only as
// published.
import gallery from "../../../examples/gallery.json";
import {
  selectPlaygroundExamples,
} from "../../scripts/playground-examples.mjs";
const sources = import.meta.glob("../../../examples/{love,magic,power}/*.x", {
  query: "?raw", import: "default", eager: true,
});
const slideSources = import.meta.glob("../content/slides/*.md", {
  query: "?raw", import: "default", eager: true,
});
const built = Object.values(import.meta.glob(
  "../../../builds/wasm/playground/programs.json",
  { import: "default", eager: true },
))[0] as string[] | undefined;
export const playgroundService: string =
  import.meta.env.PLAYGROUND_URL || "";
const programs = new Set(import.meta.env.PROD ? built ?? [] : []);

// The slide's code without the "~" lines it hides, as the site shows it.
const visibleCode = (slide: string, source: string) => {
  const block = (slideSources[`../content/slides/${slide}`] as string ?? "")
    .match(/```x2c\n([\s\S]*?)\n```/)?.[1];
  return block?.split("\n").filter((line) => !line.trimStart().startsWith("~"))
    .join("\n").trim() ?? source;
};

const sourceFor = (id: string) =>
  sources[`../../../examples/${id}.x`] as string | undefined;
export const playgroundExamples = selectPlaygroundExamples(gallery, sourceFor)
  .filter((entry) =>
    playgroundService || !programs.size || programs.has(entry.id))
  .map(({ id, slide, source }) => ({
    id, source, program: programs.has(id),
    visible: visibleCode(slide, source),
    slug: slides.find((item) => item.file?.endsWith(`/${slide}`))
      ?.frontmatter.slug,
    label: id.replaceAll("/", " / "),
  }));
// The playground runs programs with a service or precompiled programs.
export const playgroundRuns = Boolean(playgroundService) || programs.size > 0;
export const playgroundFor = (slug: string) => playgroundRuns
  ? playgroundExamples.find((entry) => entry.slug === slug) : undefined;
