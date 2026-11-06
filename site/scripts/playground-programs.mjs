// Precompile the playground examples to WebAssembly for the static site.
//
//   node scripts/playground-programs.mjs compile   before astro build
//   node scripts/playground-programs.mjs install   after astro build
//
// compile writes <id>.js and <id>.wasm under builds/wasm/playground and lists
// the programs in programs.json, which the site pages read. It rebuilds a
// program only when its source, data, compiler, runtime, or emcc changes.
// Without emcc, the compiler, or the wasm runtime it removes programs.json,
// and the site builds without precompiled programs.
// install copies the listed programs to dist/playground/programs.
import { spawn, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import {
  copyFile, mkdir, readFile, readdir, rm, writeFile
} from "node:fs/promises";
import { availableParallelism } from "node:os";
import { fileURLToPath } from "node:url";
import path from "node:path";

import {
  embeddedData, selectPlaygroundExamples
} from "./playground-examples.mjs";

const siteRoot =
  path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const root = path.resolve(siteRoot, "..");
const cache = path.join(root, "builds/wasm/playground");
const manifest = path.join(cache, "programs.json");
const compiler = path.join(root, "builds/0/x2c");
const runtime = path.join(root, "builds/wasm/libx2c.a");
const wasmBuild = path.join(root, "tools/wasm-build");
const output = path.join(siteRoot, "dist/playground/programs");

const digest = (...parts) => {
  const hash = createHash("sha256");
  for (const part of parts) hash.update(part).update("\0");
  return hash.digest("hex");
};

async function dataDigest(directory) {
  const entries = await readdir(path.join(root, directory),
    { recursive: true, withFileTypes: true });
  const files = entries.filter((entry) => entry.isFile())
    .map((entry) => path.join(entry.parentPath, entry.name)).sort();
  const contents = await Promise.all(files.map((file) => readFile(file)));
  return digest(...files, ...contents);
}

function emccVersion() {
  const result = spawnSync(process.env.WASM_CC || "emcc", ["--version"],
    { encoding: "utf8" });
  return result.status === 0 ? result.stdout : undefined;
}

function run(command, args, env) {
  return new Promise((resolve) => {
    const child = spawn(command, args,
      { cwd: root, env, stdio: ["ignore", "pipe", "pipe"] });
    let log = "";
    child.stdout.on("data", (chunk) => (log += chunk));
    child.stderr.on("data", (chunk) => (log += chunk));
    child.on("error", (error) => resolve({ status: 1, log: String(error) }));
    child.on("close", (status) => resolve({ status, log }));
  });
}

async function compileOne(example, toolchain) {
  const stem = path.join(cache, example.id);
  const data = embeddedData(example.source);
  const stamp = digest(toolchain, example.source,
    ...(await Promise.all(data.map(dataDigest))));
  const stampFile = `${stem}.stamp`;
  if (existsSync(`${stem}.js`) && existsSync(`${stem}.wasm`) &&
      existsSync(stampFile) && (await readFile(stampFile, "utf8")) === stamp)
    return false;
  const embed = data.map((directory) =>
    `--embed-file ${path.join(root, directory)}@${directory}`);
  const ldflags = [process.env.WASM_LDFLAGS, ...embed].filter(Boolean);
  await mkdir(path.dirname(stem), { recursive: true });
  const { status, log } = await run(wasmBuild,
    [path.join(root, "examples", `${example.id}.x`), stem],
    { ...process.env, WASM_LDFLAGS: ldflags.join(" ") });
  if (status !== 0)
    throw new Error(`playground: ${example.id} failed to build\n${log}`);
  await writeFile(stampFile, stamp);
  return true;
}

function missingTool() {
  if (!emccVersion()) return "emcc is not on PATH";
  if (!existsSync(compiler)) return "builds/0/x2c is missing; run make build";
  if (!existsSync(runtime))
    return "builds/wasm/libx2c.a is missing; run make wasm-runtime";
  return undefined;
}

async function compile() {
  await rm(manifest, { force: true });
  const missing = missingTool();
  if (missing) {
    console.log(`playground: skipping precompiled programs (${missing}).`);
    return;
  }
  const gallery = JSON.parse(
    await readFile(path.join(root, "examples/gallery.json"), "utf8"));
  const examples = selectPlaygroundExamples(gallery, (id) => {
    const file = path.join(root, "examples", `${id}.x`);
    return existsSync(file) ? readFileSync(file, "utf8") : undefined;
  });
  const toolchain = digest(emccVersion(), process.env.WASM_CFLAGS ?? "",
    process.env.WASM_LDFLAGS ?? "", await readFile(compiler),
    await readFile(runtime), await readFile(wasmBuild));
  const started = Date.now();
  const queue = [...examples];
  let built = 0;
  const jobs = Math.max(1, availableParallelism() >> 1);
  await Promise.all(Array.from({ length: jobs }, async () => {
    for (let example; (example = queue.shift());)
      if (await compileOne(example, toolchain)) built += 1;
  }));
  await writeFile(manifest,
    JSON.stringify(examples.map((example) => example.id)) + "\n");
  const seconds = ((Date.now() - started) / 1000).toFixed(1);
  console.log(`playground: ${examples.length} precompiled programs ` +
    `(${built} rebuilt in ${seconds} s).`);
}

async function install() {
  if (!existsSync(manifest)) return;
  const ids = JSON.parse(await readFile(manifest, "utf8"));
  for (const id of ids) {
    await mkdir(path.dirname(path.join(output, id)), { recursive: true });
    for (const suffix of [".js", ".wasm"])
      await copyFile(path.join(cache, id + suffix),
        path.join(output, id + suffix));
  }
}

const command = process.argv[2];
if (command === "compile") await compile();
else if (command === "install") await install();
else {
  console.error("usage: node scripts/playground-programs.mjs compile|install");
  process.exitCode = 2;
}
