// Build the same standalone programs used by the package's web preview.
import { spawnSync } from "node:child_process";
import { copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const root = new URL("../../", import.meta.url);
const web = new URL("packages/x2cui/builds/web/", root);
const output = new URL("site/dist/secret/", root);

function make(args) {
  const result = spawnSync("make", args, {
    cwd: fileURLToPath(root), stdio: "inherit"
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`CUI demos: make ${args.join(" ")} failed`);
}

if (process.argv[2] === "compile") {
  make(["wasm-runtime"]);
  make(["-C", "packages/x2cui", "web"]);
} else if (process.argv[2] === "install") {
  const shell = await readFile(new URL("index.html", web), "utf8");
  for (const [program, title] of [
    ["gallery", "x2c component gallery"], ["stress", "x2c stress test"]
  ]) {
    const directory = new URL(`${program}/`, output);
    await mkdir(directory, { recursive: true });
    await writeFile(new URL("index.html", directory), shell
      .replace(/<title>.*?<\/title>/, `<title>${title}</title>`)
      .replace("<body>", `<body data-program="${program}">`));
    for (const suffix of ["js", "wasm"])
      await copyFile(new URL(`${program}.${suffix}`, web),
        new URL(`${program}.${suffix}`, directory));
  }
} else {
  throw new Error("Usage: node scripts/cui-demos.mjs compile|install");
}
