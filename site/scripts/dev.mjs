import { spawn } from "node:child_process";
import { createConnection, createServer } from "node:net";
import { fileURLToPath } from "node:url";
import path from "node:path";

import { sitePath } from "../site-config.mjs";

const scriptRoot = path.dirname(fileURLToPath(import.meta.url));
const siteRoot = path.resolve(scriptRoot, "..");
const repositoryRoot = path.resolve(siteRoot, "..");
const docsRoot = path.join(repositoryRoot, "docs");
const astro = path.join(siteRoot, "node_modules", ".bin", "astro");
const children = new Set();
let stopping = false;
let finalStatus = 0;

function unusedPort() {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      server.close((error) => {
        if (error) reject(error);
        else resolve(address.port);
      });
    });
  });
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function acceptsConnections(port) {
  return new Promise((resolve) => {
    const socket = createConnection({ host: "127.0.0.1", port });
    socket.once("connect", () => {
      socket.destroy();
      resolve(true);
    });
    socket.once("error", () => resolve(false));
  });
}

async function waitForServer(child, port) {
  const deadline = Date.now() + 10000;

  while (Date.now() < deadline) {
    if (child.exitCode !== null) {
      throw new Error("mdBook stopped before its server was ready");
    }
    if (await acceptsConnections(port)) return;
    await delay(50);
  }

  throw new Error("timed out waiting for mdBook to start");
}

function stop(status) {
  if (stopping) return;
  stopping = true;
  finalStatus = status;

  for (const child of children) child.kill("SIGTERM");
  if (children.size === 0) process.exitCode = finalStatus;
}

function launch(command, args, options = {}) {
  const child = spawn(command, args, {
    cwd: repositoryRoot,
    stdio: "inherit",
    ...options
  });
  children.add(child);

  child.once("error", (error) => {
    console.error(`unable to run ${command}: ${error.message}`);
    stop(1);
  });
  child.once("exit", (status) => {
    children.delete(child);
    if (!stopping) stop(status ?? 1);
    if (stopping && children.size === 0) process.exitCode = finalStatus;
  });

  return child;
}

process.once("SIGINT", () => stop(0));
process.once("SIGTERM", () => stop(0));

try {
  const docsPort = await unusedPort();
  const docs = launch(
    process.env.MDBOOK_BIN || "mdbook",
    [
      "serve",
      docsRoot,
      "--hostname",
      "127.0.0.1",
      "--port",
      String(docsPort)
    ],
    {
      env: {
        ...process.env,
        MDBOOK_OUTPUT__HTML__SITE_URL: sitePath("/docs/"),
        MDBOOK_LOG: process.env.MDBOOK_LOG || "warn"
      }
    }
  );

  await waitForServer(docs, docsPort);
  launch(astro, ["dev", ...process.argv.slice(2)], {
    cwd: siteRoot,
    env: {
      ...process.env,
      X2C_DOCS_DEV_ORIGIN: `http://127.0.0.1:${docsPort}`
    }
  });
} catch (error) {
  console.error(error.message);
  stop(1);
}
