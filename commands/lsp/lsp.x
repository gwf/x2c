/*  lsp.x -- ordered JSON-RPC messages over framed stdio

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "positions.x"
#include "analysis.x"
#include "json.x"
#include <poll.h>
#include <errno.h>
#include <limits.h>

static typedef struct Server {
  File output;
  LspWorkspace workspace;
  Array queued;
  Map cancelled, pending, documents;
  int initialized, shutdown, exiting, eof;
} Server;

/** Serves one workspace until exit or clean EOF. */
int lsp_serve(void) {
  File output = auto File.fdopen(dup(STDOUT_FILENO), "w");
  fflush(stdout);
  if (dup2(STDERR_FILENO, STDOUT_FILENO) < 0) return 2;
  setvbuf(stdin, NULL, _IONBF, 0);
  Context session = Context.open_isolated_named("language server");
  Server server = {.output = output, .queued = [], .cancelled = {}, .pending = {}, .documents = {}};
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
    default: if (request) _error(server, id, -32601, "Method not found"); return;
  }
}

static void _initialize(Server &server, Var id, Map params) {
  if (server.initialized) { _error(server, id, -32600, "Already initialized"); return; }
  Map options = params.getdefault("initializationOptions", {});
  server.workspace = LspWorkspace.new(options.getdefault("arguments", []));
  server.initialized = 1;
  _reply(server, id, {capabilities: {
    textDocumentSync: {openClose: Json.bool(1), change: 1,
                       save: {includeText: Json.bool(1)}},
    definitionProvider: Json.bool(1), hoverProvider: Json.bool(1)},
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
                                      : server.workspace.text(path);
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
    String path = server.workspace.retain(lsp_path(change.getdefault("uri", NULL)));
    if (path) { _affected(server, path); server.workspace.invalidate(path); }
  }
}

static void _query(Server &server, Var id, Map params, int definition) {
  String path = server.workspace.retain(_document(params));
  if (!path) { _reply(server, id, NULL); return; }
  Map position = params.getdefault("position", {});
  int offset = lsp_offset(server.workspace.text(path), position);
  Var result = definition ? server.workspace.definition(path, offset)
                          : server.workspace.hover(path, offset);
  _reply(server, id, result);
  _notice(server);
}

static void _publish(Server &server) {
  if (!server.workspace || server.shutdown) return;
  Array paths = [];
  foreach (String path, server.pending.keys()) paths.push(path);
  paths = server.workspace.retain(paths);
  foreach (String path, paths) {
    Array diagnostics = server.workspace.diagnostics(path);
    Map params = {uri: lsp_uri(path), diagnostics: diagnostics};
    if (!server.pending[path].is_null()) params[<version>] = server.pending[path];
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
  Array affected = server.workspace.retain(server.workspace.affected(path));
  foreach (String document, affected)
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
