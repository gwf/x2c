const vscode = require("vscode");
const path = require("path");
const { SemanticService, byteOffset, positionAt, selectTool, findExecutable } = require("./semantic");

function activate(context) {
  const diagnostics = vscode.languages.createDiagnosticCollection("x2c");
  const output = vscode.window.createOutputChannel("x2c");
  const services = new Map();
  const errors = new Map();
  const setupErrors = new Set();
  const timers = new Map();
  const selector = { language: "x2c", scheme: "file" };
  let runtimeNotice = false;

  function serviceFor(document) {
    if (!vscode.workspace.isTrusted || document.uri.scheme !== "file") return null;
    if (typeof AbortController === "undefined") {
      if (!runtimeNotice) output.appendLine(
        "Semantic features require a newer VS Code runtime. Syntax highlighting remains available."
      );
      runtimeNotice = true;
      return null;
    }
    const settings = vscode.workspace.getConfiguration("x2c", document.uri);
    if (!settings.get("semantic.enabled", true)) return null;
    const workspace = vscode.workspace.getWorkspaceFolder(document.uri);
    const cwd = workspace ? workspace.uri.fsPath : path.dirname(document.uri.fsPath);
    const tool = selectTool(settings, workspace?.uri.fsPath);
    const worker = findExecutable(tool.worker, cwd);
    const setupKey = JSON.stringify([cwd, tool.worker]);
    if (!worker) {
      diagnostics.delete(document.uri);
      if (!setupErrors.has(setupKey)) output.appendLine(
        `Cannot execute '${tool.worker}'. Install x2c and set x2c.semantic.compilerPath ` +
        "to its executable, or place x2c on PATH. Syntax highlighting remains available."
      );
      setupErrors.add(setupKey);
      return null;
    }
    setupErrors.delete(setupKey);
    const args = settings.get("semantic.arguments", []);
    const key = JSON.stringify([cwd, worker, tool.prefix, args]);
    if (!services.has(key)) services.set(key,
      new SemanticService({ worker, prefix: tool.prefix, cwd, args }));
    const service = services.get(key);
    // Include unsaved headers, imports, and manifests, not just x2c documents.
    for (const open of vscode.workspace.textDocuments) {
      if (open.uri.scheme !== "file") continue;
      service.update(open.uri.fsPath, open.getText(), open.version, open.isDirty);
    }
    return service;
  }

  function range(result, location) {
    const text = result.texts.get(location.file);
    if (text === undefined) return null;
    const start = positionAt(text, location.start);
    const end = positionAt(text, location.end);
    return new vscode.Range(start.line, start.character, end.line, end.character);
  }

  async function analyze(document, kind, position, token) {
    const service = serviceFor(document);
    if (!service) return null;
    const controller = new AbortController();
    const cancellation = token?.onCancellationRequested(() => controller.abort());
    if (token?.isCancellationRequested) controller.abort();
    try {
      const offset = position ? byteOffset(document.getText(), document.offsetAt(position)) : 0;
      const result = await service.analyze(document.uri.fsPath, kind, offset, controller.signal);
      const file = document.uri.toString();
      if (result?.error) {
        const message = result.error.includes("ENOENT") ?
          `${result.error}\nInstall x2c and set x2c.semantic.compilerPath to its executable.` :
          result.error;
        if (errors.get(file) !== message) output.appendLine(message);
        errors.set(file, message);
      }
      else if (result) errors.delete(file);
      return result;
    }
    finally { cancellation?.dispose(); }
  }

  async function refresh(document) {
    const result = await analyze(document, "diagnostics");
    if (!result) return;
    if (result.error) {
      diagnostics.delete(document.uri);
      return;
    }
    const entries = [];
    for (const entry of result.diagnostics || []) {
      // Included-file diagnostics retain their location in the message when
      // displayed on the primary file; their precise range is related info.
      const location = range(result, entry);
      const primary = entry.file === (result.file || document.uri.fsPath);
      const message = primary ? entry.message : `${entry.file}: ${entry.message}`;
      const item = new vscode.Diagnostic(
        primary && location ? location : new vscode.Range(0, 0, 0, 0),
        message, entry.severity === "warning" ? vscode.DiagnosticSeverity.Warning :
          vscode.DiagnosticSeverity.Error
      );
      item.source = "x2c";
      if (entry.code) item.code = entry.code;
      if (!primary && location) item.relatedInformation = [new vscode.DiagnosticRelatedInformation(
        new vscode.Location(vscode.Uri.file(entry.file), location), entry.message
      )];
      entries.push(item);
    }
    diagnostics.set(document.uri, entries);
  }

  function schedule(document) {
    if (document.languageId !== "x2c" || document.uri.scheme !== "file") return;
    const key = document.uri.toString();
    clearTimeout(timers.get(key));
    timers.set(key, setTimeout(() => {
      timers.delete(key);
      refresh(document).catch((error) => output.appendLine(error.message));
    }, 200));
  }

  function changed(document) {
    for (const service of services.values()) {
      if (document.uri.scheme === "file")
        service.update(document.uri.fsPath, document.getText(), document.version, document.isDirty);
    }
    for (const open of vscode.workspace.textDocuments) schedule(open);
  }

  function reset() {
    for (const service of services.values()) service.dispose();
    services.clear();
    errors.clear();
    setupErrors.clear();
    diagnostics.clear();
    for (const document of vscode.workspace.textDocuments) schedule(document);
  }

  const watcher = vscode.workspace.createFileSystemWatcher(
    "**/*.{x,xh,xc,x2c,xmacro,xlisp,toml,h}"
  );
  function diskChanged() {
    for (const service of services.values()) service.invalidate();
    for (const document of vscode.workspace.textDocuments) schedule(document);
  }

  context.subscriptions.push(diagnostics, output, watcher,
    watcher.onDidChange(diskChanged), watcher.onDidCreate(diskChanged),
    watcher.onDidDelete(diskChanged),
    vscode.languages.registerDefinitionProvider(selector, {
      async provideDefinition(document, position, token) {
        const result = await analyze(document, "definition", position, token);
        if (!result?.definition) return null;
        const location = range(result, result.definition);
        return location && new vscode.Location(vscode.Uri.file(result.definition.file), location);
      }
    }),
    vscode.languages.registerHoverProvider(selector, {
      async provideHover(document, position, token) {
        const result = await analyze(document, "hover", position, token);
        if (!result?.hover) return null;
        const contents = new vscode.MarkdownString();
        contents.appendCodeblock(result.hover.text, "x2c");
        return new vscode.Hover(contents, range(result, result.hover) || undefined);
      }
    }),
    vscode.workspace.onDidOpenTextDocument(changed),
    vscode.workspace.onDidChangeTextDocument((event) => changed(event.document)),
    vscode.workspace.onDidSaveTextDocument(changed),
    vscode.workspace.onDidCloseTextDocument((document) => {
      for (const service of services.values()) service.close(document.uri.fsPath);
      clearTimeout(timers.get(document.uri.toString()));
      timers.delete(document.uri.toString());
      diagnostics.delete(document.uri);
      errors.delete(document.uri.toString());
      for (const open of vscode.workspace.textDocuments) schedule(open);
    }),
    vscode.workspace.onDidChangeConfiguration((event) => {
      if (event.affectsConfiguration("x2c")) reset();
    }),
    vscode.workspace.onDidGrantWorkspaceTrust(reset),
    vscode.workspace.onDidChangeWorkspaceFolders(reset),
    { dispose() {
      for (const timer of timers.values()) clearTimeout(timer);
      for (const service of services.values()) service.dispose();
    } }
  );
  for (const document of vscode.workspace.textDocuments) schedule(document);
}

module.exports = { activate };
