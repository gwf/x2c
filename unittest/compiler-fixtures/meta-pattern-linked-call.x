#include "x2c.x"
#include "meta.x"

/* A `$` call in a meta body's pattern runs while the body is translated,
   so the pattern captures through a linked source-form builder. A project
   function's call waits until the body runs. */
meta static List literal_shape(List fields) => cons(<literal>, fields);

meta static List spelling(List label) {
  match (label) {
    case %(expr ? $($source_literal_content(%(? ?text)))): {
      String written = text;
      return $!String{ $written };
    }
  }
  return $!String{ "none" };
}

meta static int is_hi(List label) {
  match (label) case %(expr ? $($literal_shape(%(? "\"hi\"")))): return 1;
  return 0;
}

macro Expression $written(Expr $label) => $spelling($label);
macro Expression $hi(Expr $label) => $is_hi($label);

int main(void) {
  printf("%s %s\n", $written("hi"), $written(42));
  printf("%d %d\n", $hi("hi"), $hi("ho"));
  return 0;
}
