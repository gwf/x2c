---
title: Sockets, HTTP, and JSON
group: Toolbox
---

```x2c
#include <assert.h>
#include "http.x"
#include "json.x"

int main(void) {
  Router routes = Router.new();
  routes.get("/api/ping", %!(HttpRequest req, HttpResponse res) =>
    res.json({ok: Json.bool(1), q: req.query["q"]}));
  HttpServer server = HttpServer.new(routes, {host: "127.0.0.1", port: 0});
  defer server.close();
  server.start();
  printf("listening on %d\n", server.port());
  Var parsed = Json.parse("{\"a\": [1, 2]}");
  assert(parsed["a"][1] == 2 && parsed.json() == "{\"a\":[1,2]}");
  return 0;
}
```

- `net.x` has blocking `Socket.connect`, `Listener.bind`, and `accept`
  over two `File` streams. `http.x` adds HTTP/1.1 routing, a worker pool,
  static files, and `Http.fail(404, "...")`.
- `time.x`, `random.x`, `encoding.x`, `url.x`, `regex.x`, `digest.x`,
  `diff.x`: include what you use.
