/*  test-http.x -- HTTP parsing, routing, responses, and loopback service */
#include "http.x"
#include "test-support.x"
#include "test-macros.x"
#include <time.h>

static File _input(String text) {
  File file = tmpfile();
  file.write_all(text, text.len());
  rewind(file);
  return file;
}

static int _rejected(String text, int limit) {
  File file = auto _input(text);
  try HttpRequest.read(file, limit);
  catch %(http-fail (status ?status) *): return status.integer();
  return 0;
}

static void http_parser(void) {
  $test.scoped();
  File file = auto _input("POST /notes/a%20b?q=two+words&tag=x HTTP/1.1\r\n"
    "Host: localhost\r\nX-Name: first\r\nx-name: second\r\nContent-Length: 2\r\n\r\n{}");
  HttpRequest req = HttpRequest.read(file, 100);
  EXPECT_TRUE(req.method == <post>);
  EXPECT_STR_EQ(req.path, "/notes/a b");
  EXPECT_STR_EQ(req.query["q"].str(), "two words");
  EXPECT_STR_EQ(req.headers["x-name"].str(), "first, second");
  EXPECT_STR_EQ(req.body, "{}");
  EXPECT_TRUE(req.keep_alive);
  EXPECT_TRUE(req.json() is <map>);
  File old = auto _input("GET / HTTP/1.0\r\n\r\n");
  EXPECT_FALSE(HttpRequest.read(old, 100).keep_alive);
  File persistent = auto _input("GET / HTTP/1.0\r\nConnection: keep-alive\r\n\r\n");
  EXPECT_TRUE(HttpRequest.read(persistent, 100).keep_alive);
  File tokens = auto _input("GET / HTTP/1.1\r\nHost: x\r\nConnection: foo, Close\r\n\r\n");
  EXPECT_FALSE(HttpRequest.read(tokens, 100).keep_alive);
  File old_tokens = auto _input("GET / HTTP/1.0\r\nConnection: Foo, keep-alive\r\n\r\n");
  EXPECT_TRUE(HttpRequest.read(old_tokens, 100).keep_alive);
  File both = auto _input("GET / HTTP/1.1\r\nHost: x\r\nConnection: keep-alive, close\r\n\r\n");
  EXPECT_FALSE(HttpRequest.read(both, 100).keep_alive);
  File reversed = auto _input("GET / HTTP/1.0\r\nConnection: , ClOsE , KEEP-ALIVE,\r\n\r\n");
  EXPECT_FALSE(HttpRequest.read(reversed, 100).keep_alive);
  File exact = auto _input("GET /plain+path?q=a+b HTTP/1.1\r\nHost: x\r\n"
    "Connection: xclose, \tkeep-alive\t,\r\n\r\n");
  HttpRequest plain = HttpRequest.read(exact, 100);
  EXPECT_STR_EQ(plain.path, "/plain+path");
  EXPECT_STR_EQ(plain.query["q"].str(), "a b");
  EXPECT_TRUE(plain.keep_alive);
  EXPECT_TRUE(plain.body == NULL);
  EXPECT_TRUE(plain.params != NULL);
  EXPECT_TRUE(plain.query != NULL);
}

static void http_parser_rejections(void) {
  $test.scoped();
  EXPECT_INT_EQ(_rejected("GET / HTTP/1.1\r\n\r\n", 100), 400);
  EXPECT_INT_EQ(_rejected("get / HTTP/1.1\r\nHost: x\r\n\r\n", 100), 405);
  EXPECT_INT_EQ(_rejected("A_VERY_LONG_UNKNOWN_METHOD / HTTP/1.1\r\nHost: x\r\n\r\n", 100), 405);
  EXPECT_INT_EQ(_rejected("GET / HTTP/1.1\r\nHost: x\r\nBad Name: x\r\n\r\n", 100), 400);
  EXPECT_INT_EQ(_rejected("BAD / HTTP/1.1\r\nHost: x\r\n\r\n", 100), 405);
  EXPECT_INT_EQ(_rejected("GET /%xx HTTP/1.1\r\nHost: x\r\n\r\n", 100), 400);
  EXPECT_INT_EQ(_rejected("GET /plain%00 HTTP/1.1\r\nHost: x\r\n\r\n", 100), 400);
  EXPECT_INT_EQ(_rejected("GET /plain%0d HTTP/1.1\r\nHost: x\r\n\r\n", 100), 400);
  EXPECT_INT_EQ(_rejected("GET /plain% HTTP/1.1\r\nHost: x\r\n\r\n", 100), 400);
  EXPECT_INT_EQ(
    _rejected("GET /plain?q=%zz HTTP/1.1\r\nHost: x\r\n\r\n", 100), 400);
  EXPECT_INT_EQ(_rejected("POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n", 100), 411);
  EXPECT_INT_EQ(_rejected("POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 101\r\n\r\n", 100), 413);
  EXPECT_INT_EQ(_rejected("POST / HTTP/1.1\r\nHost: x\r\nContent-Length: -1\r\n\r\n", 100), 400);
  EXPECT_INT_EQ(_rejected("POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 2\r\n\r\nx", 100), 400);
  EXPECT_INT_EQ(_rejected("GET / HTTP/1.1\r\nHost: x\r\n", 100), 400);
  Buffer longline = auto Buffer.new(0);
  longline.write("GET /").write_repeat('x', 8192).write(" HTTP/1.1\r\nHost: x\r\n\r\n");
  EXPECT_INT_EQ(_rejected(longline, 100), 400);
  longline.clear().write("GET / HTTP/1.1\r\nHost: x\r\nBig: ").write_repeat('x', 65536).write("\r\n\r\n");
  EXPECT_INT_EQ(_rejected(longline, 100), 431);
}

static void http_nul_framing(void) {
  $test.scoped();
  const char header[] = "GET / HTTP/1.1\r\nHost: x\r\nX: a\0b\r\n\r\n";
  File input = auto tmpfile();
  input.write_all(header, sizeof(header) - 1); rewind(input);
  int status = 0;
  try HttpRequest.read(input, 100);
  catch %(http-fail (status ?code) *): status = code.integer();
  EXPECT_INT_EQ(status, 400);
  const char body[] = "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 3\r\n\r\na\0b";
  File second = auto tmpfile();
  second.write_all(body, sizeof(body) - 1); rewind(second);
  status = 0;
  try HttpRequest.read(second, 100);
  catch %(http-fail (status ?code) *): status = code.integer();
  EXPECT_INT_EQ(status, 400);
}

static void http_router_and_response(void) {
  $test.scoped();
  Router routes = Router.new();
  routes.get("/notes/:id", %!(HttpRequest req, HttpResponse res) => res.json({"id": req.params["id"]}));
  routes.get("/files/*rest", %!(HttpRequest req, HttpResponse res) => res.text(req.params["rest"]));
  routes.get("/notes/fixed", %!(HttpRequest req, HttpResponse res) => res.text("later"));
  File file = auto _input("GET /notes/fixed HTTP/1.1\r\nHost: x\r\n\r\n");
  HttpRequest req = HttpRequest.read(file, 100);
  HttpResponse res = HttpResponse.new();
  routes.dispatch(req, res);
  EXPECT_STR_EQ(res.body.str(), "{\"id\":\"fixed\"}");
  File wire = auto tmpfile();
  res.status(201).write(wire, 0);
  rewind(wire);
  String text = wire.string();
  EXPECT_TRUE(text.contains("HTTP/1.1 201 Created\r\n"));
  EXPECT_TRUE(text.contains("content-length: 14\r\n"));
  EXPECT_TRUE(text.contains("application/json"));
  req.path = "/files/a/b";
  routes.dispatch(req, res);
  EXPECT_STR_EQ(res.body.str(), "a/b");
  int status = 0;
  req.method = <post>;
  try routes.dispatch(req, res);
  catch %(http-fail (status ?code) *): status = code.integer();
  EXPECT_INT_EQ(status, 405);
  req.path = "/absent";
  try routes.dispatch(req, res);
  catch %(http-fail (status ?code) *): status = code.integer();
  EXPECT_INT_EQ(status, 404);
  req.method = <get>; req.path = "/notes/";
  try routes.dispatch(req, res);
  catch %(http-fail (status ?code) *): status = code.integer();
  EXPECT_INT_EQ(status, 404);
  Block binary = auto Block.new(1);
  const char data[] = {'a', 0, 'b'};
  binary.append(data, 3);
  res.bytes(binary);
  EXPECT_INT_EQ(res.body.len(), 3);
  EXPECT_INT_EQ(((char *) res.body.content.bytes)[1], 0);
}

static void http_route_captures_and_json_failure(void) {
  $test.scoped();
  Router routes = Router.new();
  routes.get("/a/:discard/no", %!(HttpRequest req, HttpResponse res) => res.text("wrong"));
  routes.post("/a/:wrong", %!(HttpRequest req, HttpResponse res) => res.text("wrong"));
  routes.get("/a/:id", %!(HttpRequest req, HttpResponse res) => res.json(req.params));
  routes.get("/files/*rest", %!(HttpRequest req, HttpResponse res) => res.json(req.params));
  File file = auto _input("GET /a/value HTTP/1.1\r\nHost: x\r\n\r\n");
  HttpRequest req = HttpRequest.read(file, 100);
  Map previous = req.params;
  HttpResponse res = HttpResponse.new();
  routes.dispatch(req, res);
  EXPECT_STR_EQ(res.body.str(), "{\"id\":\"value\"}");
  EXPECT_INT_EQ(previous.len(), 0);
  EXPECT_TRUE(previous != req.params);
  EXPECT_INT_EQ(req.params.len(), 1);
  req.path = "/files/";
  routes.dispatch(req, res);
  EXPECT_STR_EQ(req.params["rest"].str(), "");

  res.text("previous body");
  int failed = 0;
  try res.json([1, Stdout]);
  catch %(bad-types *): failed = 1;
  EXPECT_TRUE(failed);
  EXPECT_INT_EQ(res.body.len(), 0);
  EXPECT_STR_EQ(res.headers["content-type"].str(), "text/plain; charset=utf-8");
  Var value = {"z": [Json.bool(1), "quote\"\n"], "a": {"nested": 2}};
  res.json(value);
  EXPECT_STR_EQ(res.body.str(), value.json());
  EXPECT_STR_EQ(res.headers["content-type"].str(), "application/json");
}

static String _response(Socket client, int &code) {
  String status = client.input.readline();
  code = status ? atoi(status + 9) : 0;
  long length = 0;
  for (;;) {
    String line = client.input.readline();
    if (!line || !line.strip(NULL)) break;
    if (line.startswith("content-length:")) length = atol(line + 15);
  }
  return client.input.readblock(length);
}

static void http_loopback(void) {
  $test.scoped();
  Path directory = Path.temp_dir();
  defer directory.remove_tree();
  directory.join("index.html").write_text("hello static");
  Router routes = Router.new();
  routes.get("/notes/:id", %!(HttpRequest req, HttpResponse res) => res.json({"id": req.params["id"]}));
  routes.post("/notes", %!(HttpRequest req, HttpResponse res) => res.status(201).json(req.json()));
  routes.get("/fail", %!(HttpRequest req, HttpResponse res) => { Http.fail(422, "rejected"); });
  routes.get("/bug", %!(HttpRequest req, HttpResponse res) => { raise %(bad-arg); });
  routes.get(
    "/bad-text",
    %!(HttpRequest req, HttpResponse res) => { raise %(malformed); });
  routes.get("/io-bug", %!(HttpRequest req, HttpResponse res) => {
    res.status(201).text("partial");
    raise %(io-fail (errno 5));
  });
  routes.route(<head>, "/head", %!(HttpRequest req, HttpResponse res) => res.text("hidden"));
  routes.files("/", directory);
  Logger logger = Logger.new(<error>);
  defer logger.free();
  List events = NULL;
  logger.add_memory_sink(&events);
  HttpServer server = HttpServer.new(routes, {host: "127.0.0.1", port: 0, workers: 2,
    logger: Var.new(<p48>, logger), <idle-ms>: 100});
  defer server.close();
  server.start();
  Socket client = auto Socket.connect("127.0.0.1", server.port(), 1000);
  client.set_timeout(2000);
  int code = 0;
  client.output.puts("GET /notes/one HTTP/1.1\r\nHost: x\r\n\r\n"); client.output.flush();
  EXPECT_STR_EQ(_response(client, code), "{\"id\":\"one\"}");
  EXPECT_INT_EQ(code, 200);
  client.output.puts("POST /notes HTTP/1.1\r\nHost: x\r\nContent-Length: 7\r\n\r\n{\"n\":1}"); client.output.flush();
  EXPECT_STR_EQ(_response(client, code), "{\"n\":1}");
  EXPECT_INT_EQ(code, 201);
  client.output.puts("GET / HTTP/1.1\r\nHost: x\r\n\r\n"); client.output.flush();
  EXPECT_STR_EQ(_response(client, code), "hello static");
  client.output.puts("GET /fail HTTP/1.1\r\nHost: x\r\n\r\n"); client.output.flush();
  EXPECT_STR_EQ(_response(client, code), "{\"error\":\"rejected\"}");
  EXPECT_INT_EQ(code, 422);
  client.output.puts("POST /notes HTTP/1.1\r\nHost: x\r\nContent-Length: 1\r\n\r\nx"); client.output.flush();
  EXPECT_STR_EQ(_response(client, code), "{\"error\":\"malformed JSON\"}");
  EXPECT_INT_EQ(code, 400);
  client.output.puts("GET /bad-text HTTP/1.1\r\nHost: x\r\n\r\n");
  client.output.flush();
  EXPECT_STR_EQ(_response(client, code), "{\"error\":\"malformed request\"}");
  EXPECT_INT_EQ(code, 400);
  client.output.puts("GET //etc/passwd HTTP/1.1\r\nHost: x\r\n\r\n"); client.output.flush();
  _response(client, code);
  EXPECT_INT_EQ(code, 404);
  client.output.puts("GET /%2fetc/passwd HTTP/1.1\r\nHost: x\r\n\r\n"); client.output.flush();
  _response(client, code);
  EXPECT_INT_EQ(code, 404);
  client.output.puts("GET /%2e%2e/etc/passwd HTTP/1.1\r\nHost: x\r\n\r\n"); client.output.flush();
  _response(client, code);
  EXPECT_INT_EQ(code, 404);
  client.output.puts("GET /io-bug HTTP/1.1\r\nHost: x\r\n\r\n"); client.output.flush();
  EXPECT_STR_EQ(_response(client, code), "{\"error\":\"internal server error\"}");
  EXPECT_INT_EQ(code, 500);
  client.output.puts("HEAD /head HTTP/1.1\r\nHost: x\r\n\r\nGET /notes/two HTTP/1.1\r\nHost: x\r\n\r\n"); client.output.flush();
  EXPECT_TRUE(client.input.readline().contains("200"));
  while (client.input.readline().strip(NULL)) { }
  EXPECT_STR_EQ(_response(client, code), "{\"id\":\"two\"}");
  client.output.puts("GET /bug HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n"); client.output.flush();
  EXPECT_STR_EQ(_response(client, code), "{\"error\":\"internal server error\"}");
  EXPECT_INT_EQ(code, 500);
  Socket idle = auto Socket.connect("127.0.0.1", server.port(), 1000);
  idle.output.puts("GET /notes/idle HTTP/1.1\r\nHost: x\r\n\r\n"); idle.output.flush();
  _response(idle, code);
  struct timespec before, after;
  clock_gettime(CLOCK_MONOTONIC, &before);
  server.stop();
  clock_gettime(CLOCK_MONOTONIC, &after);
  double seconds = after.tv_sec - before.tv_sec + (after.tv_nsec - before.tv_nsec) / 1e9;
  EXPECT_TRUE(seconds < 1.0);
  EXPECT_INT_EQ(events.len(), 2);
}

void http_suite(void) {
  $test.run(http_parser);
  $test.run(http_parser_rejections);
  $test.run(http_nul_framing);
  $test.run(http_router_and_response);
  $test.run(http_route_captures_and_json_failure);
  $test.run(http_loopback);
}
