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


// The server canonicalizes paths. Return workspace resources through the URI
// spelling VS Code already uses for its open buffers.
function uriConverters(cwd, Uri) {
  const realRoot = fs.realpathSync(cwd);
  return {
    code2Protocol: (uri) => uri.toString(),
    protocol2Code(value) {
      const uri = Uri.parse(value);
      if (uri.scheme !== "file") return uri;
      const relative = path.relative(realRoot, uri.fsPath);
      if (relative === ".." || relative.startsWith(".." + path.sep) || path.isAbsolute(relative))
        return uri;
      return Uri.file(path.join(cwd, relative));
    }
  };
}

module.exports = { findExecutable, selectCompiler, uriConverters };
