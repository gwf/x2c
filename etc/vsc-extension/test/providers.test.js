const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");
const semantic = require("../semantic");

test("providers preserve syntax in untrusted workspaces and use real spans when trusted", async () => {
  const registrations = {};
  const services = [];
  const output = [];
  let available = true;
  const noop = () => ({ dispose() {} });
  const uri = (name) => ({ scheme: "file", fsPath: name, toString: () => `file://${name}` });
  const document = { uri: uri("/project/app.x"), languageId: "x2c", version: 7,
    isDirty: true, getText: () => "/* \ud83c\udf0d */ int item;", offsetAt: () => 13 };
  const header = { uri: uri("/project/item.x"), languageId: "plaintext", version: 9,
    isDirty: true, getText: () => "int item;" };
  class FakeService {
    constructor(options) { this.options = options; this.documents = new Map(); services.push(this); }
    update(file, text, version, dirty) { this.documents.set(file, { text, version, dirty }); }
    close(file) { this.documents.delete(file); }
    dispose() {}
    async analyze(file, kind, offset) {
      this.last = { file, kind, offset };
      return { definition: { file: header.uri.fsPath, start: 4, end: 8 },
        hover: { file, start: 15, end: 19, text: "int item;" },
        texts: new Map([[file, document.getText()], [header.uri.fsPath, header.getText()]]) };
    }
  }
  const vscode = {
    workspace: { isTrusted: false, textDocuments: [document, header],
      getConfiguration: () => ({ get: (_name, fallback) => fallback,
        inspect: () => ({ defaultValue: "x2c-editor-worker" }) }),
      getWorkspaceFolder: () => ({ uri: uri("/project") }),
      onDidOpenTextDocument: noop, onDidChangeTextDocument: noop,
      onDidSaveTextDocument: noop, onDidCloseTextDocument: noop,
      onDidChangeConfiguration: noop, onDidGrantWorkspaceTrust: noop,
      onDidChangeWorkspaceFolders: noop,
      createFileSystemWatcher: () => ({ dispose() {},
        onDidChange: noop, onDidCreate: noop, onDidDelete: noop }) },
    languages: {
      createDiagnosticCollection: () => ({ set() {}, clear() {}, delete() {}, dispose() {} }),
      registerDefinitionProvider: (selector, provider) => {
        registrations.definition = { selector, provider }; return noop();
      },
      registerHoverProvider: (selector, provider) => {
        registrations.hover = { selector, provider }; return noop();
      }
    },
    window: { createOutputChannel: () => ({ appendLine: (message) => output.push(message), dispose() {} }) },
    Range: class { constructor(line, character, endLine, endCharacter) {
      Object.assign(this, { line, character, endLine, endCharacter });
    } },
    Location: class { constructor(uri, range) { Object.assign(this, { uri, range }); } },
    MarkdownString: class { appendCodeblock(text, language) { Object.assign(this, { text, language }); } },
    Hover: class { constructor(contents, range) { Object.assign(this, { contents, range }); } },
    Uri: { file: uri }
  };
  const module = { exports: {} };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, "..", "extension.js"), "utf8"), {
    module, require: (name) => name === "vscode" ? vscode : name === "./semantic" ?
      { ...semantic, SemanticService: FakeService,
        findExecutable: () => available ? "/selected/x2c" : null } : require(name),
    AbortController, setTimeout: () => 0, clearTimeout() {}
  });
  const context = { subscriptions: [] };
  module.exports.activate(context);
  const hoverProvider = registrations.hover.provider;
  assert.equal(await hoverProvider.provideHover(document, {}), null);
  assert.equal(services.length, 0, "untrusted workspace must not execute compiler macros");
  assert.equal(registrations.hover.selector.scheme, "file");
  vscode.workspace.isTrusted = true;
  const hover = await hoverProvider.provideHover(document, {});
  assert.equal(hover.contents.text, "int item;");
  assert.equal(services[0].last.offset, semantic.byteOffset(document.getText(), 13));
  assert.equal(services[0].documents.get(header.uri.fsPath).version, 9);
  const definition = await registrations.definition.provider.provideDefinition(document, {});
  assert.equal(definition.uri.fsPath, header.uri.fsPath);
  assert.equal(definition.range.character, 4);
  assert.equal(definition.range.endCharacter, 8);
  assert.equal(services[0].options.worker, "/selected/x2c");
  assert.deepEqual(Array.from(services[0].options.prefix), ["editor"]);
  available = false;
  assert.equal(await hoverProvider.provideHover(document, {}), null);
  assert.equal(await hoverProvider.provideHover(document, {}), null);
  assert.equal(output.length, 1, "missing tool setup is reported once");
  assert.match(output[0], /semantic.compilerPath/);
  available = true;
  assert.ok(await hoverProvider.provideHover(document, {}));
  for (const disposable of context.subscriptions) disposable.dispose();
});
