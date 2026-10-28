const fs = require("fs");
const path = require("path");

function findExecutable(command, cwd, searchPath = process.env.PATH || "") {
  const candidates = command.includes("/") || command.includes("\\")
    ? [path.resolve(cwd, command)]
    : searchPath.split(path.delimiter).map((directory) => path.resolve(cwd, directory, command));
  for (const candidate of candidates) {
    try {
      fs.accessSync(candidate, fs.constants.X_OK);
      if (fs.statSync(candidate).isFile()) return candidate;
    }
    catch { /* A missing compiler is reported in the extension's output. */ }
  }
  return null;
}

function selectCompiler(settings, workspace) {
  const explicit = settings.get("semantic.compilerPath", "");
  if (explicit) return explicit;
  const local = workspace && path.join(workspace, "x2c");
  return local && findExecutable(local, workspace) ? local : "x2c";
}

module.exports = { findExecutable, selectCompiler };
