const fs = require("fs").promises;
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");

// Compiler offsets count UTF-8 bytes; editor offsets count UTF-16 code units.
function byteOffset(text, offset) {
  return Buffer.byteLength(text.slice(0, offset), "utf8");
}

function textOffset(text, offset) {
  const bytes = Buffer.from(text, "utf8");
  let end = Math.min(Math.max(offset, 0), bytes.length);
  while (end > 0 && end < bytes.length && (bytes[end] & 0xc0) === 0x80) end--;
  return bytes.subarray(0, end).toString("utf8").length;
}

function positionAt(text, byte) {
  const offset = textOffset(text, byte);
  const prefix = text.slice(0, offset);
  const line = prefix.split("\n").length - 1;
  return { line, character: offset - prefix.lastIndexOf("\n") - 1 };
}

function runWorker(executable, args, options, signal) {
  return new Promise((resolve, reject) => {
    if (signal.aborted) return resolve({ cancelled: true });
    const grouped = process.platform !== "win32";
    const child = spawn(executable, args, {
      ...options, detached: grouped, stdio: ["ignore", "pipe", "pipe"]
    });
    let output = "";
    // Keep a useful error tail without retaining arbitrary macro output.
    const collect = (chunk) => { output = (output + chunk.toString()).slice(-65536); };
    child.stdout.on("data", collect);
    child.stderr.on("data", collect);
    let killTimer;
    const kill = (name) => {
      if (!child.pid) return;
      try {
        if (grouped) process.kill(-child.pid, name);
        else child.kill(name);
      }
      catch (error) { if (error.code !== "ESRCH") collect(error.message); }
    };
    const abort = () => {
      kill("SIGTERM");
      killTimer = setTimeout(() => kill("SIGKILL"), 1000);
    };
    signal.addEventListener("abort", abort, { once: true });
    child.once("error", (error) => {
      signal.removeEventListener("abort", abort);
      reject(error);
    });
    child.once("close", (code, killedBy) => {
      // The leader may exit before a native preprocessor or macro child.
      // Finish cancelling the group before snapshots are removed.
      if (signal.aborted) kill("SIGKILL");
      clearTimeout(killTimer);
      signal.removeEventListener("abort", abort);
      resolve({ code, output, killedBy, cancelled: signal.aborted });
    });
    if (signal.aborted) abort();
  });
}

class SemanticService {
  constructor({ worker, cwd, args = [], run = runWorker, tempRoot = os.tmpdir() }) {
    this.worker = worker;
    this.cwd = cwd;
    this.args = args;
    this.run = run;
    this.tempRoot = tempRoot;
    this.documents = new Map();
    this.requests = new Map();
    this.revision = 0;
  }

  update(filename, text, version, dirty = true) {
    const previous = this.documents.get(filename);
    if (previous && previous.version === version && previous.text === text &&
        previous.dirty === dirty) return;
    this.documents.set(filename, { text, version, dirty });
    this.invalidate();
  }

  close(filename) {
    if (this.documents.delete(filename)) this.invalidate();
  }

  invalidate() {
    this.revision++;
    for (const controller of this.requests.values()) controller.abort();
    this.requests.clear();
  }

  dispose() {
    this.invalidate();
    this.documents.clear();
  }

  async analyze(filename, kind = "diagnostics", offset = 0, signal) {
    const key = `${filename}\0${kind}`;
    this.requests.get(key)?.abort();
    const controller = new AbortController();
    this.requests.set(key, controller);
    const abort = () => controller.abort();
    signal?.addEventListener("abort", abort, { once: true });
    if (signal?.aborted) abort();
    const revision = this.revision;
    const documents = new Map(this.documents);
    let directory;
    try {
      if (controller.signal.aborted) return null;
      directory = await fs.mkdtemp(path.join(this.tempRoot, "x2c-editor-"));
      const response = path.join(directory, "response.json");
      const argv = [response, filename, kind, String(offset), String(documents.size)];
      let index = 0;
      for (const [logical, document] of documents) {
        const snapshot = path.join(directory, `${index++}.source`);
        await fs.writeFile(snapshot, document.text, { mode: 0o600 });
        argv.push(logical, snapshot, document.dirty ? "1" : "0");
      }
      argv.push("--", ...this.args);
      if (controller.signal.aborted) return null;
      const execution = await this.run(this.worker, argv, { cwd: this.cwd }, controller.signal);
      if (execution.cancelled || controller.signal.aborted || revision !== this.revision) return null;
      if (execution.code !== 0) {
        return { error: execution.output.trim() ||
          `x2c semantic worker failed (${execution.killedBy || execution.code}).` };
      }
      let encoded;
      try { encoded = await fs.readFile(response, "utf8"); }
      catch (error) {
        if (error.code !== "ENOENT") throw error;
        return { error: execution.output.trim() ||
          "x2c semantic worker did not produce a result." };
      }
      const result = JSON.parse(encoded);
      if (controller.signal.aborted || revision !== this.revision) return null;
      // Responses carry byte spans. Resolve against the same text snapshots.
      result.texts = new Map([...documents].map(([file, value]) => [file, value.text]));
      for (const source of result.sources || []) result.texts.set(source.file, source.text);
      return result;
    }
    catch (error) {
      if (controller.signal.aborted || revision !== this.revision) return null;
      return { error: error.message };
    }
    finally {
      signal?.removeEventListener("abort", abort);
      if (this.requests.get(key) === controller) this.requests.delete(key);
      if (directory) await fs.rm(directory, { recursive: true, force: true });
    }
  }
}

module.exports = { SemanticService, byteOffset, textOffset, positionAt, runWorker };
