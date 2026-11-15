const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

function setup() {
  const handlers = {}, clients = [], messages = [], notifications = [];
  let shown = false;
  const uri = (name) => ({ scheme: "file", fsPath: name, toString: () => `file://${name}` });
  const folder = { uri: uri("/project"), name: "project", index: 0 };
  const document = { uri: uri("/project/app.x"), languageId: "x2c", version: 7,
    getText: () => "int value;" };
  const header = { uri: uri("/project/header.h"), languageId: "c", version: 3,
    getText: () => "/* 🌍 */ int value;\r\n" };
  let available = true, failStartup = false;
  const settings = { "semantic.compilerPath": "/selected/x2c",
    "semantic.arguments": ["build", "--target", "app"] };
  const event = (name) => (fn) => { handlers[name] = fn; return { dispose() {} }; };
  const vscode = {
    workspace: {
      isTrusted: false, textDocuments: [header, document],
      getWorkspaceFolder: () => folder,
      getConfiguration: () => ({ get: (key, fallback) => settings[key] ?? fallback }),
      onDidOpenTextDocument: event("open"), onDidChangeTextDocument: event("change"),
      onDidSaveTextDocument: event("save"), onDidCloseTextDocument: event("close"),
      onDidChangeConfiguration: event("configuration"), onDidGrantWorkspaceTrust: event("trust"),
      onDidChangeWorkspaceFolders: event("folders"),
      createFileSystemWatcher: (pattern) => ({ pattern, disposed: false,
        dispose() { this.disposed = true; } })
    },
    window: {
      showErrorMessage: async (message, action) => { notifications.push(message); return action; },
      createOutputChannel: () => ({ appendLine: (text) => messages.push(text),
        show: () => { shown = true; }, dispose() {} })
    },
    RelativePattern: class { constructor(base, pattern) { Object.assign(this, { base, pattern }); } }
  };
  class LanguageClient {
    constructor(id, name, server, options) {
      Object.assign(this, { id, name, server, options, notifications: [], started: 0, disposed: 0 });
      clients.push(this);
    }
    createDefaultErrorHandler() { return { error: () => ({ action: 1 }), closed: () => ({ action: 2 }) }; }
    onDidChangeState(handler) { this.stateHandler = handler; return { dispose() {} }; }
    async start() {
      if (failStartup) throw new Error("server initialize failed");
      this.stateHandler({ newState: 2 });
      this.started++;
      await this.options.middleware.didOpen(document, async () => {
        assert.equal(this.notifications[0].method, "textDocument/didOpen");
        assert.equal(this.notifications[0].params.textDocument.uri, header.uri.toString());
      });
    }
    async dispose() {
      this.disposed++;
      if (failStartup) throw new Error("Client is not running and can't be stopped");
    }
    async sendNotification(method, params) { this.notifications.push({ method, params }); }
  }
  const module = { exports: {} };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, "..", "extension.js"), "utf8"), {
    module, require: (name) => name === "vscode" ? vscode :
      name === "vscode-languageclient/node" ? { LanguageClient, State: { Running: 2 }, CloseAction: { DoNotRestart: 1 } } :
      name === "./client" ? {
        uriConverters: (cwd) => ({ cwd }),
        selectCompiler: () => ({ selected: settings["semantic.compilerPath"],
          command: available ? "/selected/x2c" : null, reason: "x2c.semantic.compilerPath" }) } : require(name)
  });
  return { extension: module.exports, handlers, clients, messages, notifications, outputShown: () => shown, vscode, document, header,
    settings, context: { subscriptions: [] }, unavailable: () => { available = false; },
    failStartup: () => { failStartup = true; } };
}

test("trusted workspace starts one stdio client with compiler arguments and full overlays", async () => {
  const s = setup();
  await s.extension.activate(s.context);
  assert.equal(s.clients.length, 0, "untrusted workspace must not execute macros");
  s.vscode.workspace.isTrusted = true;
  await s.handlers.trust();
  const client = s.clients[0];
  assert.equal(client.started, 1);
  assert.equal(client.options.errorHandler.closed().action, 2, "running server retains normal restart policy");
  assert.match(s.messages[0], /Starting .*selected\/x2c lsp .*compilerPath/);
  assert.equal(client.server.command, "/selected/x2c");
  assert.deepEqual(Array.from(client.server.args), ["lsp"]);
  // An explicit stdio transport makes vscode-languageclient 9 append --stdio.
  assert.equal(Object.hasOwn(client.server, "transport"), false);
  assert.equal(client.server.options.cwd, "/project");
  assert.equal(client.options.uriConverters.cwd, "/project");
  assert.deepEqual(Array.from(client.options.initializationOptions.arguments), ["build", "--target", "app"]);
  assert.equal(client.options.documentSelector[0].scheme, "file");
  assert.equal(client.options.documentSelector[0].language, "x2c");
  assert.equal(client.options.workspaceFolder.uri.fsPath, "/project");
  assert.equal(client.notifications[0].method, "textDocument/didOpen");
  assert.equal(client.notifications[0].params.textDocument.text, s.header.getText());
  await s.handlers.open(s.document);
  assert.equal(s.clients.length, 1);
  assert.equal(client.notifications.length, 1, "language client owns x2c synchronization");
  // vscode-languageclient reuses the same client object after a server crash.
  await client.start();
  assert.equal(client.notifications.length, 2, "restart resends unsaved dependency overlays");
  await s.handlers.change({ document: s.header });
  assert.equal(client.notifications.at(-1).params.contentChanges[0].text, s.header.getText());
  await s.handlers.save(s.header);
  assert.equal(client.notifications.at(-1).method, "textDocument/didSave");
  await s.handlers.close(s.header);
  assert.equal(client.notifications.at(-1).method, "textDocument/didClose");
  await s.handlers.configuration({ affectsConfiguration: () => true });
  await s.extension.deactivate();
  assert.equal(client.disposed, 1);
  assert.equal(client.options.synchronize.fileEvents.disposed, true);
  assert.equal(s.clients[1].disposed, 1);
});

test("disabled and virtual documents never launch a client and missing compiler is reported once", async () => {
  const s = setup();
  s.vscode.workspace.isTrusted = true;
  s.settings["semantic.enabled"] = false;
  await s.extension.activate(s.context);
  assert.equal(s.clients.length, 0);
  s.settings["semantic.enabled"] = true;
  s.unavailable();
  await s.handlers.open(s.document);
  await s.handlers.open(s.document);
  assert.equal(s.messages.length, 1);
  assert.match(s.messages[0], /semantic.compilerPath/);
  const virtual = { ...s.document, uri: { scheme: "untitled" } };
  await s.handlers.open(virtual);
  assert.equal(s.clients.length, 0);
  await s.extension.deactivate();
});


test("failed startup reports the original server error when client disposal also rejects", async () => {
  const s = setup();
  s.vscode.workspace.isTrusted = true;
  s.failStartup();
  await s.extension.activate(s.context);
  assert.equal(s.messages.length, 2);
  assert.match(s.messages[1], /server initialize failed/);
  assert.equal(s.notifications.length, 1);
  assert.equal(s.outputShown(), true);
  assert.equal(s.clients[0].options.errorHandler.closed().action, 1);
  await s.handlers.open(s.document);
  assert.equal(s.clients.length, 1, "failed workspace is not retried on document open");
  await s.handlers.configuration({ affectsConfiguration: () => true });
  assert.equal(s.clients.length, 2, "configuration change allows a new attempt");
  assert.equal(s.clients[0].disposed, 1);
  assert.equal(s.clients[0].options.synchronize.fileEvents.disposed, true);
  await s.extension.deactivate();
});
