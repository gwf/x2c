/*  inline-lisp.x -- Drive the package's Lisp regex surface from x2c. */

import "pcre2" with RegexpLisp;

int main(void) {
  Lisp lisp = Lisp.new();
  defer lisp.destroy();
  RegexpLisp.install(lisp);

  String text = %"Order 41 ships with 3 labels";
  List result = lisp.eval(%(
    `(,(length (regex-find-all "[[:alpha:]]+" $text))
      ,(regex-replace "[0-9]+" $text "#"))
  ));
  int words;
  String redacted;
  (words, redacted) = result;
  printf("%d words: %s\n", words, redacted);

  /*  The same session composes the bindings without returning to x2c. */
  String csv = %"alpha, beta, gamma";
  puts(lisp.eval(%(
    regex-replace "," (car (regex-split ", " $csv)) ""
  )).string());
  return 0;
}
