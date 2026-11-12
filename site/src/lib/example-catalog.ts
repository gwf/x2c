import type { MarkdownInstance } from "astro";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import gallery from "../../../examples/gallery.json";
import { slides, articles, playgroundExamples } from "./examples";
import { nativeReason } from "../../scripts/playground-examples.mjs";

type ExampleMarkdown = MarkdownInstance<Record<string, any>>;
const published = new Map(playgroundExamples.map(entry => [entry.id, entry]));
const read = (path: string) =>
  readFileSync(join(import.meta.env.X2C_REPOSITORY_ROOT, path), "utf8");

// The manifest names each example's expected stdout relative to examples/.
const expected = new Map(read("examples/manifest.txt").split("\n")
  .filter((line) => line && !line.startsWith("#"))
  .map((line) => line.split("|"))
  .filter((row) => row[4] && row[4] !== "-")
  .map((row) => [`examples/${row[0]}.x`, `examples/${row[4]}`]));
const outputFor = (path: string, fallback?: string) => {
  const declared = expected.get(path) ?? fallback;
  if (declared) return read(declared);
  // Optional examples have checked output outside the core manifest.
  const file = path.startsWith("packages/")
    ? path.replace(/\/examples\/([^/]+)\.x$/, "/examples/expected/$1.stdout")
    : `examples/expected/${path.slice("examples/".length, -2).replaceAll("/", "-")}.stdout`;
  return existsSync(join(import.meta.env.X2C_REPOSITORY_ROOT, file)) ? read(file) : undefined;
};

const galleryEntries = gallery.flatMap((entry) => {
  if (entry.language) return [];
  const path = entry.example ? `examples/${entry.example}.x` : entry.source;
  if (!path?.endsWith(".x")) return [];
  const slide = slides.find((item) => item.file?.endsWith(`/${entry.slide}`))!;
  if (slide.frontmatter.section === "packages") return [];
  const id = entry.example ?? (path.startsWith("examples/")
    ? path.slice("examples/".length, -2)
    : `${slide.frontmatter.section}/${slide.frontmatter.slug}`);
  const flagFile = path.slice(0, -2) + ".flags";
  const flags = existsSync(join(import.meta.env.X2C_REPOSITORY_ROOT, flagFile))
    ? read(flagFile).trim() : "";
  const source = read(path);
  return [{
    id, section: slide.frontmatter.section, path, source,
    label: slide.frontmatter.tab
      ?? id.split("/").pop()!.replaceAll("-", " "),
    nativeReason: nativeReason(entry, source),
    program: published.get(id)?.program ?? false,
    recipe: slide.frontmatter.run?.trim()
      ?? `x2c run ${flags ? flags + " " : ""}${path}`,
    output: outputFor(path), slide,
  }];
// Home slides keep their carousel order; the others follow in gallery order.
}).sort((a, b) => (a.slide.frontmatter.order ?? Number.MAX_SAFE_INTEGER)
  - (b.slide.frontmatter.order ?? Number.MAX_SAFE_INTEGER));

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
    source,
    label: page.navTitle, program: false,
    output: outputFor(page.source, page.output), article,
    recipe: (page.run ?? recipes[page.slug]).trim(),
  };
});

// Every program on the examples page, in list order.
export const exampleEntries: {
  id: string; section: string; path: string; source: string; label: string;
  nativeReason?: string; program: boolean; output?: string;
  slide?: ExampleMarkdown;
  article?: ExampleMarkdown; recipe?: string; description?: string;
}[] = [...galleryEntries, ...programEntries];
export const exampleSections = ["love", "power", "magic", "programs"];

// All entry points use the same complete-example destination.
export const exampleRoute = (entry: typeof exampleEntries[number]) => entry.article
  ? `${entry.article.frontmatter.slug}/`
  : `${entry.section}/#${entry.id.replaceAll("/", "-")}`;
export const exampleRoutes = Object.fromEntries(
  exampleEntries.map(entry => [entry.id, exampleRoute(entry)]));
