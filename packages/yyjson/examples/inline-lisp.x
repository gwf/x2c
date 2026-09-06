/*  inline-lisp.x -- Drive the package's Lisp JSON surface from x2c. */

import "yyjson" as json;

int main(void) {
  Scope.retain();
  defer Scope.release();

  Lisp lisp = Lisp.new();
  defer lisp.destroy();
  json.JsonLisp.install(lisp);

  String source = %"{\"service\":\"artifact-api\",\"ports\":[80,443,8080]}";
  List summary = lisp.eval(%(
    `(,(json-pointer (json-parse $source) "/service")
      ,(json-len (json-pointer (json-parse $source) "/ports")))
  ));
  String service;
  int ports;
  (service, ports) = summary;
  printf("%s listens on %d ports\n", service, ports);

  /*  json-list crosses a JSON array into the List that Lisp's own car, cdr,
      and length operate on, so the reshaping happens in Lisp.
  */
  puts(lisp.eval(%(
    json-stringify (cdr (json-list (json-pointer (json-parse $source)
                                                 "/ports")))
  )).string());
  return 0;
}
