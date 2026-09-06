const DEFAULT_SITE_URL = "https://gwf.github.io";
const DEFAULT_SITE_BASE = "/x2c";
const requestedSiteBase = process.env.SITE_BASE || DEFAULT_SITE_BASE;

export const siteUrl = new URL(
  process.env.SITE_URL || DEFAULT_SITE_URL
).origin;
export const siteBase = requestedSiteBase === "/"
  ? "/"
  : `/${requestedSiteBase.replace(/^\/+|\/+$/g, "")}`;
export const sitePrefix = siteBase === "/" ? "" : siteBase;
export const socialImagePath = "/x2c-social.png";

export const unindexedHtmlFiles = new Set([
  "404.html",
  "docs/404.html",
  "docs/print.html",
  "docs/toc.html"
]);

export function sitePath(pathname = "/") {
  const absolutePath = pathname.startsWith("/")
    ? pathname
    : `/${pathname}`;

  return `${sitePrefix}${absolutePath}`;
}

export function absoluteSiteUrl(pathname = "/") {
  return new URL(sitePath(pathname), `${siteUrl}/`).href;
}

export function htmlFileRoute(relativeFile) {
  const portableFile = relativeFile.replaceAll("\\", "/");

  if (portableFile === "index.html") return "/";
  if (portableFile.endsWith("/index.html")) {
    return `/${portableFile.slice(0, -"index.html".length)}`;
  }

  return `/${portableFile}`;
}

export function isIndexedHtmlFile(relativeFile) {
  const portableFile = relativeFile.replaceAll("\\", "/");
  return portableFile.endsWith(".html") &&
    !unindexedHtmlFiles.has(portableFile);
}
