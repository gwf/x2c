import { readdir, readFile, stat } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

import {
  absoluteSiteUrl,
  htmlFileRoute,
  isIndexedHtmlFile,
  siteBase,
  sitePath,
  siteUrl,
  socialImagePath
} from "../site-config.mjs";

const scriptRoot = path.dirname(fileURLToPath(import.meta.url));
const siteRoot = path.resolve(scriptRoot, "..");
const output = path.join(siteRoot, "dist");
const siteOrigin = new URL(siteUrl).origin;
const errors = new Set();
const resolvedTargets = new Map();
let localReferenceCount = 0;
let fragmentReferenceCount = 0;

function fail(message) {
  errors.add(message);
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

function attributes(tag) {
  const result = new Map();
  const pattern =
    /([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;
  let match;

  while ((match = pattern.exec(tag)) !== null) {
    result.set(
      match[1].toLowerCase(),
      decodeHtml(match[2] ?? match[3] ?? match[4] ?? "")
    );
  }

  return result;
}

function tags(html, name) {
  return [...html.matchAll(new RegExp(`<${name}\\b[^>]*>`, "gi"))]
    .map((match) => attributes(match[0]));
}

function metadataValues(html, attribute, key) {
  return tags(html, "meta")
    .filter((tag) => tag.get(attribute) === key)
    .map((tag) => tag.get("content") ?? "");
}

function canonicalValues(html) {
  return tags(html, "link")
    .filter((tag) => (tag.get("rel") || "").split(/\s+/).includes("canonical"))
    .map((tag) => tag.get("href") ?? "");
}

function titleValue(html) {
  const match = html.match(/<title>([\s\S]*?)<\/title>/i);
  return match
    ? decodeHtml(match[1].replace(/<[^>]+>/g, "").trim())
    : null;
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
      files.push(relativeFile.split(path.sep).join("/"));
    }
  }

  return files.sort();
}

function outputCandidates(urlPath) {
  let relativePath;

  if (siteBase === "/") {
    relativePath = urlPath.replace(/^\/+/, "");
  } else if (urlPath === siteBase || urlPath === `${siteBase}/`) {
    relativePath = "";
  } else if (urlPath.startsWith(`${siteBase}/`)) {
    relativePath = urlPath.slice(siteBase.length + 1);
  } else {
    return [];
  }

  try {
    relativePath = decodeURIComponent(relativePath);
  } catch {
    return [];
  }

  if (!relativePath || relativePath.endsWith("/")) {
    return [path.join(output, relativePath, "index.html")];
  }

  return [
    path.join(output, relativePath),
    path.join(output, `${relativePath}.html`),
    path.join(output, relativePath, "index.html")
  ];
}

async function existingTarget(url) {
  if (resolvedTargets.has(url.pathname)) {
    return resolvedTargets.get(url.pathname);
  }

  for (const candidate of outputCandidates(url.pathname)) {
    try {
      const targetStat = await stat(candidate);
      if (targetStat.isFile()) {
        resolvedTargets.set(url.pathname, candidate);
        return candidate;
      }
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }
  resolvedTargets.set(url.pathname, null);
  return null;
}

const identifiers = new Map();

async function fragmentExists(filename, fragment) {
  if (!identifiers.has(filename)) {
    const html = await readFile(filename, "utf8");
    const values = new Set();

    for (const tag of html.matchAll(/<[a-z][^>]*>/gi)) {
      const attrs = attributes(tag[0]);
      if (attrs.has("id")) values.add(attrs.get("id"));
      if (attrs.has("name")) values.add(attrs.get("name"));
    }
    identifiers.set(filename, values);
  }

  let decodedFragment;
  try {
    decodedFragment = decodeURIComponent(fragment);
  } catch {
    return false;
  }
  return identifiers.get(filename).has(decodedFragment);
}

function pageUrl(relativeFile) {
  return new URL(
    sitePath(htmlFileRoute(relativeFile)),
    `${siteUrl}/`
  );
}

async function checkReferences(relativeFile, html) {
  const sourceUrl = pageUrl(relativeFile);

  for (const tag of html.matchAll(/<[a-z][^>]*>/gi)) {
    const attrs = attributes(tag[0]);

    for (const attribute of ["href", "src"]) {
      const reference = attrs.get(attribute);
      if (!reference || reference.startsWith("//")) continue;

      let target;
      try {
        target = new URL(reference, sourceUrl);
      } catch {
        fail(
          `${relativeFile}: invalid ${attribute} ` +
          JSON.stringify(reference)
        );
        continue;
      }

      if (!["http:", "https:"].includes(target.protocol) ||
          target.origin !== siteOrigin) {
        continue;
      }

      localReferenceCount += 1;
      const filename = await existingTarget(target);
      if (!filename) {
        fail(`${relativeFile}: missing target ${reference}`);
        continue;
      }

      if (target.hash.length > 1) {
        fragmentReferenceCount += 1;
        if (!await fragmentExists(filename, target.hash.slice(1))) {
          fail(`${relativeFile}: missing fragment ${reference}`);
        }
      }
    }
  }
}

function expectOne(relativeFile, values, expected, label) {
  if (values.length !== 1 || values[0] !== expected) {
    fail(
      `${relativeFile}: expected one ${label} ${JSON.stringify(expected)}, ` +
      `found ${JSON.stringify(values)}`
    );
  }
}

function checkMetadata(relativeFile, html) {
  const indexed = isIndexedHtmlFile(relativeFile);
  const canonicals = canonicalValues(html);
  const robots = metadataValues(html, "name", "robots");
  const ogUrls = metadataValues(html, "property", "og:url");

  if (!indexed) {
    if (canonicals.length) {
      fail(`${relativeFile}: unindexed page has a canonical URL`);
    }
    if (ogUrls.length) {
      fail(`${relativeFile}: unindexed page has an og:url`);
    }
    if (!robots.some((value) =>
      value.split(",").some((word) => word.trim() === "noindex")
    )) {
      fail(`${relativeFile}: unindexed page is missing noindex`);
    }
    return;
  }

  if (robots.some((value) => value.includes("noindex"))) {
    fail(`${relativeFile}: indexed page has noindex`);
  }

  const canonical = absoluteSiteUrl(htmlFileRoute(relativeFile));
  const image = absoluteSiteUrl(socialImagePath);
  const title = titleValue(html);
  const descriptions = metadataValues(html, "name", "description");

  expectOne(relativeFile, canonicals, canonical, "canonical URL");
  expectOne(relativeFile, ogUrls, canonical, "og:url");
  expectOne(
    relativeFile,
    metadataValues(html, "property", "og:type"),
    "website",
    "og:type"
  );
  expectOne(
    relativeFile,
    metadataValues(html, "property", "og:image"),
    image,
    "og:image"
  );
  expectOne(
    relativeFile,
    metadataValues(html, "property", "og:image:width"),
    "1200",
    "og:image:width"
  );
  expectOne(
    relativeFile,
    metadataValues(html, "property", "og:image:height"),
    "630",
    "og:image:height"
  );
  expectOne(
    relativeFile,
    metadataValues(html, "name", "twitter:image"),
    image,
    "twitter:image"
  );
  expectOne(
    relativeFile,
    metadataValues(html, "name", "twitter:card"),
    "summary_large_image",
    "twitter:card"
  );

  if (!title) {
    fail(`${relativeFile}: missing title`);
  } else {
    expectOne(
      relativeFile,
      metadataValues(html, "property", "og:title"),
      title,
      "og:title"
    );
    expectOne(
      relativeFile,
      metadataValues(html, "name", "twitter:title"),
      title,
      "twitter:title"
    );
  }

  if (descriptions.length !== 1 || !descriptions[0]) {
    fail(`${relativeFile}: expected one nonempty description`);
  } else {
    expectOne(
      relativeFile,
      metadataValues(html, "property", "og:description"),
      descriptions[0],
      "og:description"
    );
    expectOne(
      relativeFile,
      metadataValues(html, "name", "twitter:description"),
      descriptions[0],
      "twitter:description"
    );
  }
}

function checkInstallTarget(home) {
  const targetTags = [...home.matchAll(/<[a-z][^>]*>/gi)]
    .filter((match) => attributes(match[0]).get("id") === "install");

  if (targetTags.length !== 1 || !/^<figure\b/i.test(targetTags[0][0])) {
    fail("index.html: #install must identify exactly one figure");
  }
}

function checkBookReturnLinks(relativeFile, html) {
  const targets = tags(html, "a")
    .map((tag) => tag.get("href"))
    .filter(Boolean)
    .map((href) => {
      try {
        return new URL(href, pageUrl(relativeFile));
      } catch {
        return null;
      }
    })
    .filter(Boolean);
  const required = ["", "#love", "#install"];

  for (const hash of required) {
    const expected = new URL(`${sitePath("/")}${hash}`, `${siteUrl}/`);
    if (!targets.some((target) => target.href === expected.href)) {
      fail(
        `${relativeFile}: missing static book return link to ${expected.href}`
      );
    }
  }
}

async function checkSitemap(indexedFiles) {
  const sitemapFile = path.join(output, "sitemap.xml");
  let sitemap;
  try {
    sitemap = await readFile(sitemapFile, "utf8");
  } catch {
    fail("sitemap.xml: missing file");
    return;
  }

  const actual = [...sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)]
    .map((match) => decodeHtml(match[1]))
    .sort();
  const expected = indexedFiles
    .map((file) => absoluteSiteUrl(htmlFileRoute(file)))
    .sort();
  const actualSet = new Set(actual);
  const expectedSet = new Set(expected);

  if (actualSet.size !== actual.length) {
    fail("sitemap.xml: contains a duplicate URL");
  }
  for (const url of expectedSet) {
    if (!actualSet.has(url)) fail(`sitemap.xml: missing ${url}`);
  }
  for (const url of actualSet) {
    if (!expectedSet.has(url)) fail(`sitemap.xml: unexpected ${url}`);
  }
}

async function checkRobots() {
  const expected = [
    "User-agent: *",
    `Allow: ${sitePath("/")}`,
    `Sitemap: ${absoluteSiteUrl("/sitemap.xml")}`,
    ""
  ].join("\n");
  let actual;

  try {
    actual = await readFile(path.join(output, "robots.txt"), "utf8");
  } catch {
    fail("robots.txt: missing file");
    return;
  }

  if (actual !== expected) {
    fail("robots.txt: content does not match the configured deployment");
  }
}

const files = await htmlFiles(output);
const indexedFiles = files.filter(isIndexedHtmlFile);

for (const relativeFile of files) {
  const html = await readFile(path.join(output, relativeFile), "utf8");
  checkMetadata(relativeFile, html);
  await checkReferences(relativeFile, html);

  if (relativeFile.startsWith("docs/") &&
      isIndexedHtmlFile(relativeFile)) {
    checkBookReturnLinks(relativeFile, html);
  }
}

const home = await readFile(path.join(output, "index.html"), "utf8");
checkInstallTarget(home);

const bookHome = await readFile(
  path.join(output, "docs", "index.html"),
  "utf8"
);
if (titleValue(bookHome) !== "The x2c Book") {
  fail("docs/index.html: title must be exactly The x2c Book");
}

if (!await existingTarget(new URL(absoluteSiteUrl(socialImagePath)))) {
  fail(`${socialImagePath}: missing social image`);
}

await checkSitemap(indexedFiles);
await checkRobots();

if (errors.size) {
  for (const error of [...errors].sort()) {
    console.error(`site-check: ${error}`);
  }
  console.error(`site-check: ${errors.size} failure(s)`);
  process.exit(1);
}

console.log(
  `site-check: ${files.length} HTML files, ` +
  `${localReferenceCount} local references, ` +
  `${fragmentReferenceCount} fragments`
);
