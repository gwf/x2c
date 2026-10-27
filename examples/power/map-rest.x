/*  map-rest.x -- keyword arguments packed into a Map
*/

#include <assert.h>

/* Opens a pretend connection; options default when a key is absent. */
static String connect(String host, Map @options) {
  int port = options.getdefault(<port>, 80).integer();
  String scheme = options.getdefault(<scheme>, "http").str();
  return %"$scheme://$host:$port";
}

static int count(Map @options) => options.len();

int main(void) {
  Map secure = {scheme: "https", port: 443};
  puts(connect("example.org"));
  puts(connect("example.org", port: 8080));
  puts(connect("example.org", @secure));
  puts(connect("example.org", @secure, port: 8443));

  Func dynamic = connect;
  assert(dynamic("localhost", port: 3000).str() == "http://localhost:3000");
  assert(count() == 0 && count(a: 1, a: 2) == 1);
  puts("Later entries win; splices merge in place.");
  return 0;
}
