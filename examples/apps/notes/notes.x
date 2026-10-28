/*  notes.x -- a persistent notes service over the blocking HTTP runtime */
#include "service.x"
#include <assert.h>
#include <signal.h>
#include <unistd.h>

static volatile sig_atomic_t stopping;
static void _stop(int signum) { stopping = 1; }

int main(int argc, char **argv) {
  String host = "127.0.0.1";
  int port = 8080, workers = 8, check = 0;
  Path path = "notes.json";
  Path public_dir = "examples/apps/notes/public";
  Path policy = "examples/apps/notes/policy.xlisp";
  for (int i = 1; i < argc; i++) {
    String argument = argv[i];
    if (argument == "--check") check = 1;
    else if (i + 1 >= argc) raise %(bad-arg (argument $argument));
    else if (argument == "--host") host = argv[++i];
    else if (argument == "--port") port = atoi(argv[++i]);
    else if (argument == "--workers") workers = atoi(argv[++i]);
    else if (argument == "--store") path = argv[++i];
    else if (argument == "--public") public_dir = argv[++i];
    else if (argument == "--policy") policy = argv[++i];
    else raise %(bad-arg (argument $argument));
  }
  if (check) {
    path = %"/tmp/x2c-notes-$((int) getpid()).json";
    path.remove_file();
    port = 0;
    workers = 2;
  }
  MapStore backend = MapStore.open(path);
  defer backend.close();
  NoteStore store = backend.note_store();
  defer store.close();
  Router routes = notes_routes(store, public_dir, policy);
  Map options = {host: host, port: port, workers: workers};
  Logger quiet = check ? Logger.new(<off>) : NULL;
  defer if (quiet) quiet.free();
  if (check) options[<logger>] = Var.new(<p48>, quiet);
  HttpServer server = HttpServer.new(routes, options);
  server.start();
  defer server.close();
  if (check) {
    _check(server);
    server.stop();
    path.remove_file();
    return 0;
  }
  signal(SIGINT, _stop);
  signal(SIGTERM, _stop);
  printf("notes listening on %s:%d\n", host, server.port());
  fflush(stdout);
  while (!stopping) usleep(50000);
  return 0;
}

static Var _request(HttpServer server, String method, String target,
                    String body, int expected) {
  Socket peer = Socket.connect("127.0.0.1", server.port(), 2000);
  defer peer.close();
  peer.set_timeout(2000);
  peer.output.printf("%s %s HTTP/1.1\r\nHost: localhost\r\n"
    "Connection: close\r\nContent-Length: %d\r\n\r\n%s",
    method, target, body.len(), body ? body : "");
  peer.output.flush();
  String line = peer.input.readline();
  if (atoi(line[9:]) != expected) fprintf(stderr, "%s %s: %s", method, target, line);
  assert(atoi(line[9:]) == expected);
  int length = 0;
  while ((line = peer.input.readline()) && line != "\r\n" && line != "\n")
    if (line.lower().startswith("content-length:")) length = atoi(line[15:]);
  String response = peer.input.readblock(length);
  return Json.parse(response);
}

static void _check(HttpServer server) {
  for (int i = 0; i < 3; i++) {
    Map note = {"title": %"Note $(i + 1)", "body": "hello",
                "tags": [i < 2 ? "work" : "home"]};
    Map created = _request(server, "POST", "/api/notes",
                           ((Var) note).json(), 201);
    assert(created["id"].string() == %"$(i + 1)");
  }
  puts("created: 3");
  Array found = _request(server, "GET", "/api/notes?tag=work&q=Note", NULL, 200);
  assert(found.len() == 2);
  puts("search work /Note/: 2");
  Map stats = _request(server, "GET", "/api/stats", NULL, 200);
  assert(stats["tags"].map()["work"].int() == 2);
  puts("tags: home=1 work=2");
  _request(server, "POST", "/api/notes", "{\"body\":\"missing title\"}", 422);
  puts("invalid note: 422");
  _request(server, "POST", "/api/notes",
    "{\"title\":\"Blocked\",\"tags\":[\"forbidden\"]}", 422);
  puts("policy rejected forbidden tag: 422");
  _request(server, "DELETE", "/api/notes/2", NULL, 200);
  Array remaining = _request(server, "GET", "/api/notes", NULL, 200);
  assert(remaining.len() == 2);
  puts("deleted: 2; remaining: 2");
}
