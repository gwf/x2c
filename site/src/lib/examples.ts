import type { MarkdownInstance } from "astro";

type ExampleMarkdown = MarkdownInstance<Record<string, any>>;

const files = import.meta.glob<ExampleMarkdown>("../content/slides/*.md", {
  eager: true,
});

// Filename order controls presentation; frontmatter slugs keep links stable.
export const slides = Object.keys(files).sort().map((path) => files[path]);
export const inSection = (name: string) =>
  slides.filter((slide) => slide.frontmatter.section === name);

const firstSample = (slide: ExampleMarkdown) =>
  slide.rawContent().match(/```x2c\n([\s\S]*?)```/)?.[1].split("\n") ?? [];

// Line numbers of a slide's first sample that are not in the previous slide's
// sample, found through their longest common subsequence.
export const changedLines = (previous: ExampleMarkdown,
  slide: ExampleMarkdown) => {
  const before = firstSample(previous), after = firstSample(slide);
  const common = before.map(() => new Array(after.length + 1).fill(0));
  common.push(new Array(after.length + 1).fill(0));
  for (let i = before.length - 1; i >= 0; i--)
    for (let j = after.length - 1; j >= 0; j--)
      common[i][j] = before[i] === after[j] ? common[i + 1][j + 1] + 1
        : Math.max(common[i + 1][j], common[i][j + 1]);
  const changed = new Set<number>();
  for (let i = 0, j = 0; j < after.length;) {
    if (i < before.length && before[i] === after[j]) i++, j++;
    else if (i < before.length && common[i + 1][j] >= common[i][j + 1]) i++;
    else changed.add(j++);
  }
  return changed;
};

export const articles = Object.values(
  import.meta.glob<ExampleMarkdown>("../content/examples/*.md", { eager: true }),
).sort((a, b) => a.frontmatter.order - b.frontmatter.order);
export const articleFor = (slug: string) =>
  articles.find((article) =>
    !article.frontmatter.customPage && article.frontmatter.slide === slug);
