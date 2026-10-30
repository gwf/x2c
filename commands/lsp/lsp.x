/*  lsp.x -- ordered JSON-RPC messages over framed stdio

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "positions.x"
#include "analysis.x"
#include "completion.x"
#include "symbols.x"
#include "references.x"
#include "json.x"
#include <poll.h>
#include <errno.h>
#include <limits.h>
#include <fcntl.h>
#include <dirent.h>

static typedef struct Server {
  File output;
  LspWorkspace workspace;
  Array queued, arguments;
  Map cancelled, pending, documents;
  int initialized, shutdown, exiting, eof, baseline_warm, restart_disabled;
  size_t baseline;
} Server;

static typedef struct Cursor {
  String path;
  int offset;
} Cursor;

/** Serves one workspace until exit or clean EOF. */
int lsp_serve(int resume) {
  File output = auto File.fdopen(dup(STDOUT_FILENO), "w");
  if (fcntl(output.fileno(), F_SETFD, FD_CLOEXEC) < 0) return 2;
  fflush(stdout);
  if (dup2(STDERR_FILENO, STDOUT_FILENO) < 0) return 2;
  setvbuf(stdin, NULL, _IONBF, 0);
  Context session = Context.open_isolated_named("language server");
  Server server = {.output = output, .queued = [], .cancelled = {},
                   .pending = {}, .documents = {}};
  if (resume >= 0) _restore(server, resume);
  server.baseline = _retained_bytes();
  while (!server.exiting) {
    if (!server.queued.len() && !server.eof) _receive(server);
    while (!server.eof && _waiting()) _receive(server);
    if (server.queued.len()) {
      Map message = server.queued[0];
      server.queued.remslice(0, 1);
      _dispatch(server, message);
      _discard(message);
    }
    else if (server.eof) break;
    if (!server.queued.len() && (server.eof || !_waiting())) _publish(server);
    if (!server.queued.len() && !server.pending.len() && !server.eof &&
        !server.shutdown && !server.exiting && !_waiting()) _checkpoint(server);
  }
  if (server.workspace) server.workspace.close_unit();
  int result = server.exiting && !server.shutdown ? 1 : 0;
  session.close();
  return result;
}

static int _waiting(void) {
  struct pollfd input = {.fd = STDIN_FILENO, .events = POLLIN};
  int result;
  do result = poll(&input, 1, 0); while (result < 0 && errno == EINTR);
  return result > 0 && (input.revents & (POLLIN | POLLHUP));
}

static void _send(Server &server, Map message) {
  String body = Var.json(message);
  server.output.printf("Content-Length: %d\r\n\r\n%s", body.len(), body);
  server.output.flush();
}

static void _reply(Server &server, Var id, Var result) =>
  _send(server, {jsonrpc: "2.0", id: id, result: result});

static void _error(Server &server, Var id, int code, String message) =>
  _send(server, {jsonrpc: "2.0", id: id,
                 error: {code: code, message: message}});

/* Unbuffered stdin keeps poll's view consistent with the framing reader. */
static String _frame(Server &server) {
  String line = Stdin.readline();
  if (!line) { server.eof = 1; return NULL; }
  long length = -1;
  int malformed = 0;
  while (line != "\n" && line != "\r\n") {
    if (!strncasecmp(line, "Content-Length:", 15)) {
      char *end;
      errno = 0;
      long parsed = strtol(line + 15, &end, 10);
      while (*end == ' ' || *end == '\t' || *end == '\r' || *end == '\n') end++;
      if (errno || *end || parsed < 0 || parsed > INT_MAX || length >= 0)
        malformed = 1;
      length = parsed;
    }
    line = Stdin.readline();
    if (!line) { server.eof = 1; raise %(lsp-frame); }
  }
  if (malformed || length < 0 || length > INT_MAX)
    raise %(lsp-frame);
  String body = Stdin.readblock(length);
  if (body.len() != length) { server.eof = 1; raise %(lsp-frame); }
  return body;
}

/* Promote messages through the retained unit into the server's lifetime. */
static void _receive(Server &server) {
  Context request = Context.open_isolated_named("language server message");
  Map message = NULL;
  try {
    String body = _frame(server);
    if (!server.eof) {
      Var parsed = Json.parse(body);
      if (parsed is not <map>) raise %(lsp-frame);
      message = request.export(parsed);
    }
  }
  catch %(*failure): _error(server, NULL, -32700, "Parse error");
  request.close();
  if (message == NULL) return;
  if (server.workspace) message = server.workspace.retain(message);
  String method = message.getdefault("method", NULL);
  if (method == "$/cancelRequest") {
    Map params = message.getdefault("params", {});
    if (params.contains("id"))
      foreach (Map queued, server.queued)
        if (queued.contains("id") && queued["id"] == params["id"])
          server.cancelled[params["id"]] = 1;
    _discard(message);
  }
  else server.queued.push(message);
}

static void _dispatch(Server &server, Map message) {
  String method = message.getdefault("method", NULL);
  int request = message.contains("id");
  Var id = message.getdefault("id", NULL);
  if (request && server.cancelled.contains(id)) {
    server.cancelled.del(id);
    _error(server, id, -32800, "Request cancelled");
    return;
  }
  if (method == "exit") { server.exiting = 1; return; }
  if (server.shutdown) {
    if (request) _error(server, id, -32600, "Server has shut down");
    return;
  }
  Map params = message.getdefault("params", {});
  if (method == "initialize") { _initialize(server, id, params); return; }
  if (!server.initialized) {
    if (request) _error(server, id, -32002, "Server not initialized");
    return;
  }
  switch (method) {
    case "initialized": return;
    case "shutdown": server.shutdown = 1; _reply(server, id, NULL); return;
    case "textDocument/didOpen": _open(server, params); return;
    case "textDocument/didChange": _change(server, params); return;
    case "textDocument/didSave": _save(server, params); return;
    case "textDocument/didClose": _close(server, params); return;
    case "workspace/didChangeWatchedFiles": _watched(server, params); return;
    case "textDocument/hover": _query(server, id, params, 0); return;
    case "textDocument/definition": _query(server, id, params, 1); return;
    case "textDocument/completion": _completion(server, id, params); return;
    case "textDocument/documentSymbol": _symbols(server, id, params); return;
    case "workspace/symbol": _workspace_symbols(server, id, params); return;
    case "textDocument/references": _references(server, id, params); return;
    case "textDocument/rename": _rename(server, id, params); return;
    default:
      if (request) _error(server, id, -32601, "Method not found");
      return;
  }
}

static void _initialize(Server &server, Var id, Map params) {
  if (server.initialized) {
    _error(server, id, -32600, "Already initialized");
    return;
  }
  Map options = params.getdefault("initializationOptions", {});
  server.arguments = options.getdefault("arguments", []).array().copy();
  server.workspace = LspWorkspace.new(server.arguments);
  server.initialized = 1;
  _reply(server, id, {capabilities: {
    textDocumentSync: {openClose: Json.bool(1), change: 1,
                       save: {includeText: Json.bool(1)}},
    definitionProvider: Json.bool(1), hoverProvider: Json.bool(1),
    completionProvider: {triggerCharacters: [".", ">", "$"]},
    documentSymbolProvider: Json.bool(1), workspaceSymbolProvider: Json.bool(1),
    referencesProvider: Json.bool(1), renameProvider: Json.bool(1)},
    serverInfo: {name: "x2c"}});
}

static String _document(Map params) {
  Map document = params.getdefault("textDocument", {});
  return lsp_path(document.getdefault("uri", NULL));
}

static void _open(Server &server, Map params) {
  String path = server.workspace.retain(_document(params));
  if (!path) return;
  Map document = params["textDocument"];
  _affected(server, path);
  if (document.getdefault("languageId", "") == "x2c")
    server.documents[path] = document.getdefault("version", NULL);
  String text = document.getdefault("text", ""), disk = "";
  int dirty = !SourceView.read(NULL, path, disk) || disk != text;
  server.workspace.change(path, text, dirty);
  _pending(server, path, document.getdefault("version", NULL));
}

static void _change(Server &server, Map params) {
  String path = server.workspace.retain(_document(params));
  if (!path) return;
  Array changes = params.getdefault("contentChanges", []);
  if (!changes.len()) return;
  Map change = changes[-1], document = params["textDocument"];
  _affected(server, path);
  server.workspace.change(path, change.getdefault("text", ""), 1);
  _pending(server, path, document.getdefault("version", NULL));
}

static void _save(Server &server, Map params) {
  String path = server.workspace.retain(_document(params));
  if (!path) return;
  String text = params.contains("text") ? params["text"].str()
                                      : server.workspace.document(path);
  text = server.workspace.retain(text);
  _affected(server, path);
  server.workspace.change(path, text, 0);
  _pending(server, path, server.documents.getdefault(path, NULL));
}

static void _close(Server &server, Map params) {
  String path = server.workspace.retain(_document(params));
  if (!path) return;
  _affected(server, path);
  server.workspace.close_document(path);
  server.documents.del(path);
  server.pending.del(path);
  _send(server, {jsonrpc: "2.0", method: "textDocument/publishDiagnostics",
                 params: {uri: lsp_uri(path), diagnostics: []}});
}

static void _watched(Server &server, Map params) {
  foreach (Map change, params.getdefault("changes", []).array()) {
    String uri = change.getdefault("uri", NULL);
    String path = server.workspace.retain(lsp_path(uri));
    if (path) { _affected(server, path); server.workspace.invalidate(path); }
  }
}

static void _query(Server &server, Var id, Map params, int definition) {
  Cursor cursor = _cursor(server, params);
  if (!cursor.path) { _reply(server, id, NULL); return; }
  Var result = definition
    ? server.workspace.definition(cursor.path, cursor.offset)
    : server.workspace.hover(cursor.path, cursor.offset);
  _reply(server, id, result);
  _notice(server);
}

static Cursor _cursor(Server &server, Map params) {
  String path = server.workspace.retain(_document(params));
  int offset = path ? lsp_offset(server.workspace.text(path),
    params.getdefault("position", {}).map()) : 0;
  return (Cursor) {.path = path, .offset = offset};
}

static void _completion(Server &server, Var id, Map params) {
  Cursor cursor = _cursor(server, params);
  _reply(server, id, cursor.path
    ? server.workspace.complete(cursor.path, cursor.offset) : (Var) {0});
  _notice(server);
}

static void _symbols(Server &server, Var id, Map params) {
  String path = server.workspace.retain(_document(params));
  _reply(server, id, path ? server.workspace.document_symbols(path) : []);
  _notice(server);
}

static void _workspace_symbols(Server &server, Var id, Map params) {
  _reply(server, id,
    server.workspace.workspace_symbols(params.getdefault("query", "")));
}

static void _references(Server &server, Var id, Map params) {
  Cursor cursor = _cursor(server, params);
  if (!cursor.path) { _reply(server, id, []); return; }
  Map context = params.getdefault("context", {});
  _answer(server, id, server.workspace.references(
    cursor.path, cursor.offset,
    Json.boolean(context.getdefault("includeDeclaration", Json.bool(0)))));
}

static void _rename(Server &server, Var id, Map params) {
  Cursor cursor = _cursor(server, params);
  if (!cursor.path) {
    _error(server, id, -32602, "Rename requires a file document");
    return;
  }
  _answer(server, id, server.workspace.rename(
    cursor.path, cursor.offset, params.getdefault("newName", "")));
}

static void _answer(Server &server, Var id, Map answer) {
  Map message = {jsonrpc: "2.0", id: id};
  if (answer.contains("error")) message[<error>] = answer["error"];
  else message[<result>] = answer["result"];
  _send(server, message);
  _notice(server);
}

static void _publish(Server &server) {
  if (!server.workspace || server.shutdown || server.exiting) return;
  Array paths = [];
  foreach (String path, server.pending.keys()) paths.push(path);
  paths = server.workspace.retain(paths);
  foreach (String path, paths) {
    Array diagnostics = server.workspace.diagnostics(path);
    Map params = {uri: lsp_uri(path), diagnostics: diagnostics};
    if (!server.pending[path].is_null())
      params[<version>] = server.pending[path];
    _send(server, {jsonrpc: "2.0", method: "textDocument/publishDiagnostics",
                   params: params});
    server.pending.del(path);
    _notice(server);
  }
}

static void _notice(Server &server) {
  String message = server.workspace.take_notice();
  if (message) _send(server, {jsonrpc: "2.0", method: "window/showMessage",
                             params: {type: 2, message: message}});
}

/* Only documents registered as x2c receive their own diagnostics. Other open
   buffers still supply overlays and invalidate documents that read them. */
static void _pending(Server &server, String path, Var version) {
  if (!server.documents.contains(path)) return;
  server.documents[path] = version;
  server.pending[path] = version;
}

static void _affected(Server &server, String path) {
  foreach (String document, server.workspace.affected(path))
    if (server.documents.contains(document))
      server.pending[document] = server.documents[document];
}

/* Parsed JSON is a tree. Surviving overlays borrow only immutable Strings. */
static void _discard(Var value) {
  if (value is <map>) {
    Map object = value;
    foreach ((Var key, Var child) in object) _discard(child);
    object.cleanup();
  }
  else if (value is <array>) {
    Array array = value;
    foreach (Var child, array) _discard(child);
    array.free();
  }
}

/* A cold baseline bounds overlay-only traffic. Reset it once after the first
   completed unit to include cold compiler setup in the generation baseline. */
static void _checkpoint(Server &server) {
  if (!server.workspace || server.restart_disabled) return;
  size_t retained = _retained_bytes();
  if (!server.baseline_warm && server.workspace.unit.context) {
    server.baseline = retained;
    server.baseline_warm = 1;
  }
  if (retained <= server.baseline ||
      retained - server.baseline < 64 * 1024 * 1024)
    return;
  server.workspace.close_unit();
  Context checkpoint =
    auto Context.open_isolated_named("language server checkpoint");
  try _restart(server);
  catch %(*failure): {
    server.restart_disabled = 1;
    Stderr.printf("x2c lsp: idle restart failed: %s\n", failure.repr());
    _send(server, {jsonrpc: "2.0", method: "window/showMessage", params: {
      type: 2, message: "x2c lsp: could not reclaim retained history; "
                       "restart the language server when convenient"}});
  }
}

/* Only exported data crosses exec. No queued request or borrowed compiler
   value is checkpointed; the protocol descriptor remains the same pipe. */
static void _restart(Server &server) {
  File saved = tmpfile();
  if (!saved) raise %(lsp-exec (operation "tmpfile"));
  defer saved.close();
  Map state = {arguments: server.arguments, documents: server.documents,
    overlays: server.workspace.sources.overlays,
    dirty: server.workspace.sources.dirty_paths,
    analyses: server.workspace.analyses, notices: server.workspace.notices,
    notice: server.workspace.notice};
  String text = Var.json(state);
  saved.write_all(text, text.len());
  if (saved.flush() || saved.seek(0, SEEK_SET) ||
      fcntl(saved.fileno(), F_SETFD, 0) < 0)
    raise %(lsp-exec (operation "checkpoint"));
  Compiler.use_meta_helper(NULL);
  Map descriptors = {};
  defer _restore_descriptors(descriptors);
  _close_on_exec(saved.fileno(), descriptors);
  fflush(stdout);
  if (dup2(server.output.fileno(), STDOUT_FILENO) < 0)
    raise %(lsp-exec (operation "stdout"));
  defer dup2(STDERR_FILENO, STDOUT_FILENO);
  char descriptor[32];
  snprintf(descriptor, sizeof(descriptor), "%d", saved.fileno());
  String executable = x2c_get_executable();
  Stderr.puts("x2c lsp: restarting after retained allocation growth\n");
  execl(executable, executable, "--lsp-resume", descriptor, (char *) NULL);
  int error = errno;
  raise %(lsp-exec (operation "exec") (errno $error));
}

static void _restore(Server &server, int descriptor) {
  Context restore = Context.open_isolated_named("language server restore");
  File saved = File.fdopen(descriptor, "r");
  Map state = restore.export(Json.parse(saved.string_close()));
  restore.close();
  server.arguments = state["arguments"];
  server.documents = state["documents"];
  server.workspace = LspWorkspace.new(server.arguments);
  server.workspace.sources.overlays = state["overlays"];
  server.workspace.sources.dirty_paths = state["dirty"];
  server.workspace.analyses = state["analyses"];
  server.workspace.notices = state["notices"];
  server.workspace.notice = state["notice"];
  server.initialized = 1;
}

/* A native module may own ordinary File descriptors. Preserve their flags if
   exec fails; successful exec keeps only stdio and the checkpoint file. */
static void _close_on_exec(int checkpoint, Map descriptors) {
  DIR *directory = opendir("/dev/fd");
  if (!directory) raise %(lsp-exec (operation "descriptors"));
  defer closedir(directory);
  struct dirent *entry;
  while ((entry = readdir(directory))) {
    if (entry->d_name[0] < '0' || entry->d_name[0] > '9') continue;
    int descriptor = atoi(entry->d_name);
    if (descriptor < 3 || descriptor == checkpoint) continue;
    int flags = fcntl(descriptor, F_GETFD);
    if (flags < 0 || flags & FD_CLOEXEC) continue;
    descriptors[descriptor] = flags;
    if (fcntl(descriptor, F_SETFD, flags | FD_CLOEXEC) < 0)
      raise %(lsp-exec (operation "descriptors"));
  }
}

static void _restore_descriptors(Map descriptors) {
  foreach ((int descriptor, int flags) in descriptors)
    fcntl(descriptor, F_SETFD, flags);
}

static size_t _retained_bytes(void) =>
  Scope.stats().live_requested_bytes + Pool.stats(Pool.current()).backing_bytes;
