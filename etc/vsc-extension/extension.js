const vscode = require("vscode");
const path = require("path");
const { LanguageClient, State, CloseAction } = require("vscode-languageclient/node");
const { selectCompiler, uriConverters } = require("./client");

let active;

function activate(context) {
  const output = vscode.window.createOutputChannel("x2c");
  const clients = new Map();
  const reported = new Set();
  const failed = new Set();
  let pending = Promise.resolve();
  let disposed = false;

  function report(message) {
    if (reported.has(message)) return;
    reported.add(message);
    output.appendLine(message);
    void vscode.window.showErrorMessage(message, "Show Output").then((choice) => {
      if (choice) output.show(true);
    });
  }

  function rootFor(document) {
    const folder = vscode.workspace.getWorkspaceFolder(document.uri);
    return { folder, cwd: folder ? folder.uri.fsPath : path.dirname(document.uri.fsPath) };
  }

  // Non-x2c documents can be unsaved includes or project manifests. The
  // language client owns x2c synchronization; forward only the other buffers.
  async function overlay(method, document) {
    if (document.uri.scheme !== "file" || document.languageId === "x2c") return;
    const entry = clients.get(rootFor(document).cwd);
    if (!entry) return;
    const textDocument = { uri: document.uri.toString(), version: document.version };
    if (method === "didOpen") Object.assign(textDocument,
      { languageId: document.languageId, text: document.getText() });
    const params = { textDocument };
    if (method === "didChange") params.contentChanges = [{ text: document.getText() }];
    if (method === "didSave") params.text = document.getText();
    await entry.client.sendNotification(`textDocument/${method}`, params);
  }

  async function start(document) {
    if (disposed || !vscode.workspace.isTrusted || document.uri.scheme !== "file" ||
        document.languageId !== "x2c") return;
    const settings = vscode.workspace.getConfiguration("x2c", document.uri);
    if (!settings.get("semantic.enabled", true)) return;
    const { folder, cwd } = rootFor(document);
    if (clients.has(cwd) || failed.has(cwd)) return;
    const { command, selected, reason } = selectCompiler(settings, cwd);
    if (!command) {
      failed.add(cwd);
      report(`Cannot execute '${selected}' (${reason}). Install x2c or set ` +
        "x2c.semantic.compilerPath to its executable, then reload the window.");
      return;
    }
    output.appendLine(`Starting ${command} lsp (${reason}); workspace: ${cwd}`);
    const watcher = vscode.workspace.createFileSystemWatcher(new vscode.RelativePattern(
      cwd, "**/*.{x,xh,xc,x2c,xp,xlisp,toml,h}"));
    let initialOverlays, defaultErrorHandler;
    let running = false;
    const client = new LanguageClient("x2c", "x2c", {
      command, args: ["lsp"], options: { cwd }
    }, {
      documentSelector: [{ language: "x2c", scheme: "file",
        pattern: new vscode.RelativePattern(cwd, "**/*") }],
      workspaceFolder: folder,
      errorHandler: {
        error: (...args) => defaultErrorHandler.error(...args),
        closed: () => running ? defaultErrorHandler.closed() :
          { action: CloseAction.DoNotRestart, handled: true }
      },
      uriConverters: uriConverters(cwd, vscode.Uri),
      initializationOptions: { arguments: settings.get("semantic.arguments", []) },
      synchronize: { fileEvents: watcher }, outputChannel: output,
      middleware: { async didOpen(open, next) {
        initialOverlays ??= Promise.all(vscode.workspace.textDocuments
          .filter((buffer) => buffer.uri.scheme === "file" && rootFor(buffer).cwd === cwd)
          .map((buffer) => overlay("didOpen", buffer)));
        await initialOverlays;
        return next(open);
      } }
    });
    defaultErrorHandler = client.createDefaultErrorHandler();
    const state = client.onDidChangeState(({ newState }) => {
      running = newState === State.Running;
      if (running) initialOverlays = undefined;
    });
    clients.set(cwd, { client, watcher, state });
    try {
      await client.start();
    }
    catch (error) {
      clients.delete(cwd);
      failed.add(cwd);
      state.dispose();
      watcher.dispose();
      report(`Cannot start '${command} lsp': ${error.message}. ` +
        "See x2c Output for the server error. Install matching x2c commands, " +
        "or run make commands for a checkout, then reload the window.");
      // The client rejects stop() when startup never reached Running.
      try { await client.dispose(); }
      catch { /* The original startup error is already reported. */ }
    }
  }

  async function stop() {
    const entries = [...clients.values()];
    clients.clear();
    await Promise.all(entries.map(async ({ client, watcher, state }) => {
      state.dispose();
      watcher.dispose();
      await client.dispose();
    }));
  }

  function enqueue(action) {
    pending = pending.then(action).catch((error) => output.appendLine(error.message));
    return pending;
  }

  function restart() {
    return enqueue(async () => {
      await stop();
      reported.clear();
      failed.clear();
      for (const document of vscode.workspace.textDocuments) await start(document);
    });
  }

  context.subscriptions.push(
    vscode.workspace.onDidOpenTextDocument((document) => enqueue(async () => {
      await start(document);
      await overlay("didOpen", document);
    })),
    vscode.workspace.onDidChangeTextDocument(({ document }) => enqueue(() => overlay("didChange", document))),
    vscode.workspace.onDidSaveTextDocument((document) => enqueue(() => overlay("didSave", document))),
    vscode.workspace.onDidCloseTextDocument((document) => enqueue(() => overlay("didClose", document))),
    vscode.workspace.onDidChangeConfiguration((event) => {
      if (event.affectsConfiguration("x2c")) return restart();
    }),
    vscode.workspace.onDidGrantWorkspaceTrust(restart),
    vscode.workspace.onDidChangeWorkspaceFolders(restart),
    { dispose() { disposed = true; enqueue(stop).finally(() => output.dispose()); } }
  );
  active = () => { disposed = true; return enqueue(stop); };
  return restart();
}

function deactivate() { return active?.(); }

module.exports = { activate, deactivate };
