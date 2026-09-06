/*  inline-lisp.x -- Drive the package's Lisp HTTP surface from x2c. */

import "libcurl" with CurlLisp;

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  String base = String.new(argv[1]);

  Lisp lisp = Lisp.new();
  defer lisp.destroy();
  CurlLisp.install(lisp);

  /*  A returned body is an ordinary Lisp string and a returned status is an
      ordinary Lisp number, so Lisp measures, slices, and counts with them.
  */
  String guide = base + %"/guide";
  List summary = lisp.eval(%(
    `(,(string-length (http-get $guide))
      ,(substring (http-get $guide) 13 31)
      ,(+ 1000 (http-status ${base + %"/ok"}))
      ,(length (http-headers ${base + %"/ok"})))
  ));
  int bytes, status, headers;
  String title;
  (bytes, title, status, headers) = summary;
  printf("%s", %"$bytes bytes, <$title>, status+1000 $status, ");
  printf("%s", %"$headers headers\n");

  /*  A definition in the session maps the binding over a list of URLs and
      trims each page down in Lisp, without returning to x2c between calls.
  */
  lisp.eval(%(
    defun title (url)
      (let ((page (http-get url)))
        (substring page 13 (- (string-length page) 15)))
  ));
  List pages = %(${base + %"/guide"} ${base + %"/reference"});
  foreach(String found, lisp.eval(%( map title '$pages )).list())
    printf("%s", %"title: $found\n");

  /*  url-escape composes into a request the session builds itself, and a
      404 stays an ordinary value a conditional can test.
  */
  puts(lisp.eval(%(
    http-get (string-append ${base + %"/search?q="} (url-escape "a & b"))
  )).string());
  puts(lisp.eval(%(
    if (= (http-status ${base + %"/missing"}) 404) "absent" "present"
  )).string());
  puts(lisp.eval(%(
    string-append "echoed: "
      (substring (http-post ${base + %"/echo"} "text/plain" "ping") 10 14)
  )).string());
  return 0;
}
