#include "x2c.x"

/* A source-literal pattern handed to a runtime Match operation lowers to a
   process-lifetime site. An interpolated pattern keeps the per-call entry;
   the expected C pins both halves of that choice. */

static int bound(List form) {
  List bindings = form.match(%(call ?callee ?args));
  if (!bindings) return -1;
  return bindings.assoc(<?args>).list().len();
}

static int sentinel(List form) =>
  form.match(%(nothing here)) ? 1 : 0;

static List renamed(List form) =>
  form.match_replace(%(call ?callee ?args), %(invoke ?callee ?args));

static List retagged(List form) =>
  form.search_replace(%(old ?value), %(new ?value));

static int first_call(List form) {
  Var found, List bindings;
  if (!form.try_search(%(call ?callee ?), &found, &bindings)) return 0;
  return bindings.assoc(<?callee>) == <f>;
}

// the interpolated leaf makes this pattern a different value per call
static List dropped(List form, Var leaf) =>
  form.search_replace(%(drop $leaf), %(kept));

int main(void) {
  printf("%d %d %d\n",
    bound(%(call f (1 2))), bound(%(other)), sentinel(%(nothing here)));
  printf("%s\n", renamed(%(call f (1))).repr());
  printf("%s\n", retagged(%((old 1) (old 2))).repr());
  printf("%d %d\n", first_call(%(wrap (call f 1))), first_call(%(wrap)));
  printf("%s\n", dropped(%((drop a) (drop b)), <a>).repr());
  return 0;
}
