import { readFileSync } from "node:fs";
import { join } from "node:path";
import galleryScript from "./from-c-gallery.js?raw";
import galleryStyle from "../styles/from-c-viewer.css?raw";
const read = (path: string) => readFileSync(join(import.meta.env.X2C_REPOSITORY_ROOT, path), "utf8");
export function viewerAsset(asset: string) {
  let body: string;
  if (asset === "snapshots.js") {
    const manifest = JSON.parse(read("examples/c2x2c/versions.json"));
    manifest.versions = manifest.versions.map((version: { label: string; path: string; append?: string[] }, index: number) => ({
      label: `V${index}`, filename: version.path,
      source: [version.path, ...(version.append ?? [])].map(path => read(`examples/c2x2c/${path}`)).join("\n"),
    }));
    body = `window.TUTORIAL_SNAPSHOTS = ${JSON.stringify(manifest)};`;
  } else {
    body = read(`tools/version-viewer/${asset}`);
    if (asset === "index.html") body = body.replace("</head>", '<meta name="robots" content="noindex">\n</head>');
    if (asset === "style.css") body += "\n" + galleryStyle;
    if (asset === "app.js") body = body
      .replace("selected = versions.length - 1;", "selected = Math.min(1, versions.length - 1);")
      .replace('if (!matchMedia("(max-width: 700px)").matches) return;', "") + "\n" + galleryScript;
  }
  const type = asset.endsWith(".html") ? "text/html" : asset.endsWith(".css") ? "text/css" : "text/javascript";
  return new Response(body, { headers: { "Content-Type": `${type}; charset=utf-8` } });
};
