/*  http.x -- blocking HTTP/1.1 routing and worker-pool service

    Copyright (c) 2026 Gary William Flake
*/
#pragma once
#include "net.x"
#include "json.x"
#include "path.x"
#include "url.x"
#include "channel.x"
#include <ctype.h>
#include <errno.h>
#include <strings.h>
#include <unistd.h>

/** One request, allocated in the current request Context. */
class HttpRequest {
  Symbol method;
  String path, body;
  Map query, headers, params;
  int keep_alive;
} *;

/** A buffered response. Nothing is sent until the handler returns. */
class HttpResponse {
  int code;
  Map headers;
  Buffer body;
} *;

static typedef struct HttpRoute {
  Symbol method;
  List segments;
  Func handler;
} *HttpRoute;

/** Routes are tried in registration order within each method. */
class Router { Array routes; } *;

/** A blocking acceptor with a bounded Channel and joined worker Threads. */
class HttpServer {
  Router router;
  Listener listener;
  Channel channel;
  Array threads;
  Thread acceptor;
  Logger logger;
  int workers, idle_ms, body_limit, owns_logger, running;
} *;

/** The receiverless owner of Http.fail. */
typedef Symbol Http;

/** Raises an expected HTTP error before any response bytes are sent.
    Raises: `<http-fail>` with `status` and `reason` details.
*/
void Http.fail(int status, String reason) {
  raise %(http-fail (status $status) (reason $reason));
}

/** Reads one bounded request; clean EOF returns NULL.
    Raises: `<http-fail>` with a 4xx `status` for a malformed, oversized, or
    unsupported request, including an invalid percent escape in the URL, or
    `<io-fail>` when reading `input` fails.
*/
HttpRequest HttpRequest.read(File input, int body_limit) {
  String first = _line(input, 8192, 400);
  if (!first) {
    if (feof(input)) return NULL;
    Http.fail(400, "empty request line");
  }
  List parts = first.split(" ");
  if (parts.len() != 3) Http.fail(400, "malformed request line");
  String method = parts[0], target = parts[1], version = parts[2];
  if (version != "HTTP/1.1" && version != "HTTP/1.0")
    Http.fail(400, "unsupported HTTP version");
  if (!target || target[0] != '/') Http.fail(400, "invalid request target");
  HttpRequest req = Scope.calloc(1, sizeof(struct HttpRequest));
  if (!_method(method)) Http.fail(405, "unsupported method");
  req.method = Symbol.new(method);
  req.headers = {}; req.params = {};
  _decode_target(req, target);
  int used = 0;
  for (;;) {
    String line = _line(input, 65536 - used, 431);
    if (!line) {
      if (feof(input)) Http.fail(400, "incomplete headers");
      break;
    }
    used += line.len() + 2;
    int colon = line.find(":");
    if (colon <= 0) Http.fail(400, "malformed header");
    String name = String.new_len(line, colon).lower();
    if (!_header_name(name)) Http.fail(400, "invalid header name");
    String value = String.new(line + colon + 1).strip(NULL);
    if (req.headers.contains(name)) {
      if (name == "content-length") Http.fail(400, "duplicate content length");
      value = String.format("%s, %s", req.headers[name].str(), value);
    }
    req.headers[name] = value;
  }
  if (version == "HTTP/1.1" &&
      (!req.headers.contains("host") || !req.headers["host"].str()))
    Http.fail(400, "Host is required");
  if (req.headers.contains("transfer-encoding"))
    Http.fail(411, "transfer encoding is unsupported");
  long length = 0;
  if (req.headers.contains("content-length")) {
    String text = req.headers["content-length"];
    if (!text) Http.fail(400, "invalid content length");
    for (int i = 0; i < text.len(); i++) {
      if (text[i] < '0' || text[i] > '9')
        Http.fail(400, "invalid content length");
      length = length * 10 + text[i] - '0';
      if (length > body_limit) Http.fail(413, "body too large");
    }
  }
  if (length) {
    try req.body = input.readblock(length);
    catch %(bad-arg *): Http.fail(400, "body is not text");
  }
  if (req.body.len() != length) Http.fail(400, "incomplete body");
  String connection = req.headers.contains("connection") ?
    req.headers["connection"].str() : NULL;
  req.keep_alive = _keep_alive(connection, version == "HTTP/1.1");
  return req;
}

/** Parses the request body as JSON. */
Var HttpRequest.json(HttpRequest req) => Json.parse(req.body);

/** Creates an empty 200 response. */
HttpResponse HttpResponse.new(void) {
  HttpResponse res = Scope.calloc(1, sizeof(struct HttpResponse));
  res.code = 200; res.headers = {}; res.body = Buffer.new(0);
  return res;
}

/** Sets the response status and returns the response. */
HttpResponse HttpResponse.status(HttpResponse res, int code) {
  res.code = code; return res;
}

/** Sets a response header.
    Raises: `<bad-arg>` for a name that is not an HTTP token or a value that
    contains CR or LF.
*/
HttpResponse HttpResponse.header(HttpResponse res, String name, String value) {
  if (!_header_name(name) || value.find("\r") >= 0 || value.find("\n") >= 0)
    raise %(bad-arg (operation "HttpResponse.header"));
  res.headers[name.lower()] = value;
  return res;
}

/** Replaces the body with UTF-8 text. */
HttpResponse HttpResponse.text(HttpResponse res, String text) {
  res.body.clear().write(text);
  res.headers["content-type"] = "text/plain; charset=utf-8";
  return res;
}

/** Replaces the body with JSON. */
HttpResponse HttpResponse.json(HttpResponse res, Var value) {
  res.body.clear();
  int written = 0;
  defer if (!written) res.body.clear();
  _x2c_json_write(res.body, value, 0);
  written = 1;
  res.headers["content-type"] = "application/json";
  return res;
}

/** Replaces the body with arbitrary bytes, including embedded NUL. */
HttpResponse HttpResponse.bytes(HttpResponse res, Block bytes) {
  res.body.clear();
  res.body.content.append(bytes.bytes, bytes.length * bytes.width);
  return res;
}

/** Writes a complete response and flushes once. */
void HttpResponse.write(HttpResponse res, File output, int keep_alive) =>
  _write(res, output, keep_alive, 0);

static void _write(
  HttpResponse res, File output, int keep_alive, int head_only) {
  Buffer head = auto Buffer.new(0);
  head.printf("HTTP/1.1 %d %s\r\n", res.code, _reason(res.code));
  res.headers["content-length"] = String.printf("%ld", (long) res.body.len());
  res.headers["connection"] = keep_alive ? "keep-alive" : "close";
  foreach (Var (name, value) in res.headers)
    head.printf("%s: %s\r\n", name, value);
  head.write("\r\n");
  output.write_all(head.content.bytes, head.len());
  if (!head_only && res.code != 204 && res.code != 304)
    output.write_all(res.body.content.bytes, res.body.len());
  if (output.flush()) File.path_error("HttpResponse.write", NULL, errno);
}

/** Creates a router with no routes. */
Router Router.new(void) {
  Router router = Scope.calloc(1, sizeof(struct Router));
  router.routes = [];
  return router;
}

/** Registers a method, segment pattern, and two-argument handler. */
Router Router.route(Router r, Symbol method, String pattern, Func handler) {
  HttpRoute route = Scope.calloc(1, sizeof(struct HttpRoute));
  route.method = method;
  route.segments = pattern.split("/");
  route.handler = handler;
  r.routes.push(Var.new(<p48>, route));
  return r;
}

/** Registers GET. */
Router Router.get(Router r, String p, Func fn) => r.route(<get>, p, fn);

/** Registers POST. */
Router Router.post(Router r, String p, Func fn) => r.route(<post>, p, fn);

/** Registers PUT. */
Router Router.put(Router r, String p, Func fn) => r.route(<put>, p, fn);

/** Registers DELETE. */
Router Router.delete(Router r, String p, Func fn) => r.route(<delete>, p, fn);

/** Serves files below directory, with index.html for directories. */
Router Router.files(Router router, String prefix, Path directory) {
  String pattern = String.format(
    "%s%s*rest", prefix, prefix.endswith("/") ? "" : "/");
  return router.get(
    pattern, %!(HttpRequest req, HttpResponse res) => {
    String rest = req.params["rest"];
    if (rest.startswith("/")) Http.fail(404, "not found");
    foreach (String segment in rest.split("/"))
      if (segment == "..") Http.fail(404, "not found");
    Path path = directory.join(rest);
    if (path.is_dir()) path = path.join("index.html");
    if (!path.is_file()) Http.fail(404, "not found");
    File file = auto File.open(path, "rb");
    file.read_into(res.body.content);
    res.header("Content-Type", _mime(path.extension()));
  });
}

/** Calls the first matching handler; unmatched paths raise 404 or 405. */
void Router.dispatch(Router router, HttpRequest req, HttpResponse res) {
  int found = 0;
  List segments = req.path.split("/");
  foreach (Var entry in router.routes) {
    HttpRoute route = entry.pointer();
    if (!_match(route.segments, segments)) continue;
    found = 1;
    if (route.method != req.method) continue;
    Map captures = {};
    _capture(route.segments, segments, captures);
    req.params = captures;
    route.handler(req, res);
    return;
  }
  Http.fail(found ? 405 : 404, found ? "method not allowed" : "not found");
}

/** Binds immediately; port 0 selects an available port.
    Options use Symbol keys.
    Raises: `<bad-arg>` for fewer than one worker, an idle timeout below one
    millisecond, a negative body limit, or an invalid port, `<not-found>`
    when the host does not resolve, or `<io-fail>` on a host failure while
    binding, as `Listener.bind` does.
*/
HttpServer HttpServer.new(Router router, Map options) {
  HttpServer s = Scope.calloc(1, sizeof(struct HttpServer));
  s.router = router;
  s.workers = options.contains(<workers>) ? options[<workers>].integer() : 8;
  s.idle_ms = options.contains(<idle-ms>)
    ? options[<idle-ms>].integer() : 5000;
  s.body_limit = options.contains(<body-limit>)
    ? options[<body-limit>].integer() : 1048576;
  if (s.workers < 1 || s.idle_ms < 1 || s.body_limit < 0)
    raise %(bad-arg (operation "HttpServer.new"));
  s.logger = options.contains(<logger>) ? options[<logger>].pointer() : NULL;
  if (!options.contains(<logger>)) {
    s.logger = Logger.new(<info>);
    s.logger.add_stderr_sink();
    s.owns_logger = 1;
  }
  String host = options.contains(<host>) ? options[<host>].str() : "::";
  int port = options.contains(<port>) ? options[<port>].integer() : 8080;
  s.listener = Listener.bind(host, port);
  s.channel = Channel.new(<i32>, s.workers);
  s.threads = [];
  return s;
}

/** Reports the bound port. */
int HttpServer.port(HttpServer s) => s.listener.port();

/** Runs on the caller until stop; closes the queue and joins every worker. */
void HttpServer.serve(HttpServer s) {
  s.running = 1;
  defer { s.listener.close(); s.running = 0; }
  defer {
    s.channel.close();
    Thread.finish_all(s.threads);
  }
  for (int i = 0; i < s.workers; i++)
    s.threads.push(Thread.start(_worker, Var.new(<p48>, s)));
  for (;;) {
    int fd = _x2c_net_accept_fd(s.listener);
    if (fd < 0) break;
    int sent = 0;
    defer if (!sent) close(fd);
    s.channel.send(fd); sent = 1;
  }
}

/** Starts serving on a joined background Thread.
    Raises: `<bad-state>` when the server is already serving, or the causes
    of `Thread.start`.
*/
void HttpServer.start(HttpServer s) {
  if (s.acceptor || s.running)
    raise %(bad-state (operation "HttpServer.start"));
  s.acceptor = Thread.start(_accept, Var.new(<p48>, s));
}

/** Stops accepting and joins the background acceptor when one was started. */
void HttpServer.stop(HttpServer s) {
  s.listener.stop();
  if (s.acceptor) {
    Thread thread = s.acceptor; s.acceptor = NULL;
    defer thread.free();
    thread.join();
  }
}

/** Stops and releases native resources.
    Call after synchronous serve returns. */
void HttpServer.close(HttpServer s) {
  if (!s) return;
  s.stop(); s.listener.close(); s.channel.free();
  if (s.owns_logger) s.logger.free();
}

static String _line(File input, int limit, int status) {
  if (limit < 2) Http.fail(status, "headers too large");
  char bytes[65536];
  int size = 0;
  flockfile(input);
  defer funlockfile(input);
  for (;;) {
    int byte = getc_unlocked(input);
    if (byte == EOF) {
      input.readblock(0);
      if (size) Http.fail(400, "incomplete line");
      return NULL;
    }
    if (!byte) Http.fail(400, "NUL in header");
    if (size >= limit || size >= (int) sizeof(bytes))
      Http.fail(status, "line too large");
    bytes[size++] = byte;
    if (byte == '\n') break;
  }
  if (size < 2 || bytes[size - 2] != '\r') Http.fail(400, "CRLF required");
  return String.new_len(bytes, size - 2);
}

/* Decodes the path and query of `target`. Decoded URL text holds no CR or
   LF, which could split a header or a log line. */
static void _decode_target(HttpRequest req, String target) {
  String decoded = NULL;
  try decoded = target.percent_decode();
  catch %(malformed *): Http.fail(400, "invalid percent escape in URL");
  if (strpbrk(decoded, "\r\n")) Http.fail(400, "invalid URL byte");
  int question = target.find("?");
  req.path = (question < 0 ? target : target[:question]).percent_decode();
  req.query = question < 0 ? {} : Url.parse_query(target[question + 1:]);
}

static int _method(String method) =>
  method == "GET" || method == "POST" || method == "PUT" ||
  method == "DELETE" || method == "HEAD" || method == "OPTIONS" ||
  method == "PATCH";

static int _keep_alive(String values, int keep) {
  const char *start = values;
  while (start && *start) {
    const char *comma = strchr(start, ',');
    const char *end = comma ? comma : start + strlen(start);
    while (start < end && strchr(" \t\n\v\f\r", (unsigned char) *start))
      start++;
    while (end > start && strchr(" \t\n\v\f\r", (unsigned char) end[-1]))
      end--;
    size_t size = end - start;
    if (size == 5 && !strncasecmp(start, "close", size)) return 0;
    if (size == 10 && !strncasecmp(start, "keep-alive", size)) keep = 1;
    start = comma ? comma + 1 : NULL;
  }
  return keep;
}

static int _header_name(String name) {
  if (!name) return 0;
  for (int i = 0; i < name.len(); i++) {
    int byte = (unsigned char) name[i];
    if (!isalnum(byte) && !strchr("!#$%&'*+-.^_`|~", byte)) return 0;
  }
  return 1;
}

static int _match(List pattern, List path) {
  while (pattern) {
    String segment = pattern.car(); pattern = pattern.cdr();
    if (segment && segment[0] == '*') return !pattern;
    if (!path) return 0;
    String value = path.car(); path = path.cdr();
    if (segment && segment[0] == ':') {
      if (!value) return 0;
    }
    else if (segment != value) return 0;
  }
  return !path;
}

static void _capture(List pattern, List path, Map captures) {
  while (pattern) {
    String segment = pattern.car(); pattern = pattern.cdr();
    if (segment && segment[0] == '*') {
      captures[String.new(segment + 1)] = String.join("/", path);
      return;
    }
    String value = path.car(); path = path.cdr();
    if (segment && segment[0] == ':')
      captures[String.new(segment + 1)] = value;
  }
}

static const char *_reason(int code) {
  switch (code) {
    case 200: return "OK"; case 201: return "Created";
    case 204: return "No Content"; case 400: return "Bad Request";
    case 404: return "Not Found"; case 405: return "Method Not Allowed";
    case 411: return "Length Required"; case 413: return "Content Too Large";
    case 422: return "Unprocessable Content";
    case 431: return "Request Header Fields Too Large";
    case 500: return "Internal Server Error";
    default: return "Response";
  }
}

static String _mime(String ext) {
  Map types = {
    ".html": "text/html; charset=utf-8", ".css": "text/css",
    ".js": "text/javascript", ".json": "application/json",
    ".txt": "text/plain", ".svg": "image/svg+xml", ".png": "image/png",
    ".jpg": "image/jpeg", ".gif": "image/gif", ".ico": "image/x-icon"};
  return types.contains(ext) ? types[ext].str() : "application/octet-stream";
}

static Var _accept(Var value) {
  HttpServer s = value.pointer();
  s.serve();
  return void;
}

static Var _worker(Var value) {
  HttpServer s = value.pointer();
  foreach (int fd in s.channel) {
    Context connection = auto Context.open_isolated_named("connection");
    Socket peer = auto Socket.adopt(fd);
    peer.set_timeout(s.idle_ms);
    try _connection(s, peer);
    catch %(io-fail *): { }
  }
  return void;
}

static void _connection(HttpServer s, Socket peer) {
  for (;;) {
    Context context = auto Context.open_isolated_named("request");
    HttpResponse res = HttpResponse.new();
    HttpRequest req = NULL;
    int keep = 0;
    try {
      try req = HttpRequest.read(peer.input, s.body_limit);
      catch %(io-fail *): return;
      if (!req) return;
      keep = req.keep_alive;
      s.router.dispatch(req, res);
    }
    catch %(http-fail (status ?status) (reason ?reason)): {
      res = HttpResponse.new();
      res.status(status.integer()).json({"error": reason});
    }
    catch %(malformed (operation "Json.parse") *): {
      res = HttpResponse.new();
      res.status(400).json({"error": "malformed JSON"});
    }
    catch %(malformed *): {
      res = HttpResponse.new();
      res.status(400).json({"error": "malformed request"});
    }
    catch %(?code *detail): {
      s.logger.error(<http>, %(code $code), %(detail $detail));
      res = HttpResponse.new();
      res.status(500).json({"error": "internal server error"});
    }
    _write(res, peer.output, keep, req && req.method == <head>);
    s.logger.info(
      <http>, %(status $(res.code)), %(path $(req ? req.path : NULL)));
    if (!keep || __atomic_load_n(&s.listener.stopped, __ATOMIC_ACQUIRE))
      return;
  }
}

/** Initializes zeroed HttpRequest storage without acquiring resources. */
void HttpRequest.init(HttpRequest value) { memset(value, 0, sizeof(*value)); }
