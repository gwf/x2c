import { spawnSync } from "node:child_process";
import { readdir, readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

import {
  absoluteSiteUrl,
  htmlFileRoute,
  isIndexedHtmlFile,
  sitePath,
  socialImagePath
} from "../site-config.mjs";

const scriptRoot = path.dirname(fileURLToPath(import.meta.url));
const siteRoot = path.resolve(scriptRoot, "..");
const repositoryRoot = path.resolve(siteRoot, "..");
const docsRoot = path.join(repositoryRoot, "docs");
const siteOutput = path.join(siteRoot, "dist");
const bookOutput = path.join(siteOutput, "docs");

function escapeAttribute(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll('"', "&quot;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

function escapeXml(value) {
  return escapeAttribute(value).replaceAll("'", "&apos;");
}

function decodeHtml(value) {
  return value
    .replace(/&#x([0-9a-f]+);/gi, (_, digits) =>
      String.fromCodePoint(Number.parseInt(digits, 16)))
    .replace(/&#([0-9]+);/g, (_, digits) =>
      String.fromCodePoint(Number.parseInt(digits, 10)))
    .replaceAll("&quot;", '"')
    .replaceAll("&apos;", "'")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&amp;", "&");
}

function titleFrom(html, relativeFile) {
  const match = html.match(/<title>([\s\S]*?)<\/title>/i);
  if (!match) throw new Error(`${relativeFile}: missing title`);
  return decodeHtml(match[1].replace(/<[^>]+>/g, "").trim());
}

function descriptionFrom(html, relativeFile) {
  const tag = html.match(
    /<meta\b(?=[^>]*\bname=["']description["'])[^>]*>/i
  );
  const content = tag?.[0].match(/\bcontent=(["'])(.*?)\1/i);
  if (!content) throw new Error(`${relativeFile}: missing description`);
  return decodeHtml(content[2]);
}

function stripRobotsMetadata(html) {
  return html.replace(
    /\s*<meta\b(?=[^>]*\bname=["']robots["'])[^>]*>/gi,
    ""
  );
}

function insertIntoHead(html, metadata, relativeFile) {
  if (!/<\/head>/i.test(html)) {
    throw new Error(`${relativeFile}: missing closing head tag`);
  }
  return html.replace(/\s*<\/head>/i, `\n${metadata}\n    </head>`);
}

function indexedMetadata(title, description, canonical) {
  const escapedTitle = escapeAttribute(title);
  const escapedDescription = escapeAttribute(description);
  const escapedCanonical = escapeAttribute(canonical);
  const image = escapeAttribute(absoluteSiteUrl(socialImagePath));

  return [
    "        <!-- x2c publication metadata -->",
    `        <link rel="canonical" href="${escapedCanonical}">`,
    "        <meta property=\"og:type\" content=\"website\">",
    `        <meta property="og:title" content="${escapedTitle}">`,
    `        <meta property="og:description" content="${escapedDescription}">`,
    `        <meta property="og:url" content="${escapedCanonical}">`,
    `        <meta property="og:image" content="${image}">`,
    "        <meta property=\"og:image:width\" content=\"1200\">",
    "        <meta property=\"og:image:height\" content=\"630\">",
    "        <meta name=\"twitter:card\" content=\"summary_large_image\">",
    `        <meta name="twitter:title" content="${escapedTitle}">`,
    "        <meta name=\"twitter:description\" " +
      `content="${escapedDescription}">`,
    `        <meta name="twitter:image" content="${image}">`
  ].join("\n");
}

async function htmlFiles(root, relativeRoot = "") {
  const entries = await readdir(path.join(root, relativeRoot), {
    withFileTypes: true
  });
  const files = [];

  for (const entry of entries) {
    const relativeFile = path.join(relativeRoot, entry.name);
    if (entry.isDirectory()) {
      files.push(...await htmlFiles(root, relativeFile));
    } else if (entry.isFile() && entry.name.endsWith(".html")) {
      files.push(relativeFile);
    }
  }

  return files.sort();
}

async function finalizeBook() {
  const files = await htmlFiles(bookOutput);

  for (const bookFile of files) {
    const relativeFile = path.posix.join(
      "docs",
      bookFile.split(path.sep).join("/")
    );
    const filename = path.join(bookOutput, bookFile);
    let html = await readFile(filename, "utf8");

    if (relativeFile === "docs/index.html") {
      html = html.replace(
        "<title>The x2c Book - The x2c Book</title>",
        "<title>The x2c Book</title>"
      );
    }

    if (isIndexedHtmlFile(relativeFile)) {
      const canonical = absoluteSiteUrl(htmlFileRoute(relativeFile));
      html = insertIntoHead(
        html,
        indexedMetadata(
          titleFrom(html, relativeFile),
          descriptionFrom(html, relativeFile),
          canonical
        ),
        relativeFile
      );
    } else {
      html = stripRobotsMetadata(html);
      html = insertIntoHead(
        html,
        '        <meta name="robots" content="noindex">',
        relativeFile
      );
    }

    await writeFile(filename, html);
  }
}

async function writePublicationFiles() {
  const files = await htmlFiles(siteOutput);
  const urls = files
    .map((file) => file.split(path.sep).join("/"))
    .filter(isIndexedHtmlFile)
    .map((file) => absoluteSiteUrl(htmlFileRoute(file)))
    .sort();
  const sitemap = [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
    ...urls.map((url) => `  <url><loc>${escapeXml(url)}</loc></url>`),
    "</urlset>",
    ""
  ].join("\n");
  const robots = [
    "User-agent: *",
    `Allow: ${sitePath("/")}`,
    `Sitemap: ${absoluteSiteUrl("/sitemap.xml")}`,
    ""
  ].join("\n");

  await writeFile(path.join(siteOutput, "sitemap.xml"), sitemap);
  await writeFile(path.join(siteOutput, "robots.txt"), robots);
}

const result = spawnSync(
  process.env.MDBOOK_BIN || "mdbook",
  ["build", docsRoot, "--dest-dir", bookOutput],
  {
    cwd: repositoryRoot,
    env: {
      ...process.env,
      MDBOOK_OUTPUT__HTML__SITE_URL: sitePath("/docs/")
    },
    stdio: "inherit"
  }
);

if (result.error) {
  console.error(`unable to run mdbook: ${result.error.message}`);
  process.exit(1);
}

if (result.status !== 0) process.exit(result.status ?? 1);

await finalizeBook();
await writePublicationFiles();
