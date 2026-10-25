#include "x2c.x"

#include "macro-source-text-import.x"

macro Expression $source(Expr $syntax) =>
  $Code.source_text($syntax);

macro Expression $forward(Expr $syntax) =>
  $source($syntax);

meta static String saved_source(Source syntax) {
  Source saved = syntax;
  return Code.source_text(saved);
}

macro Expression $source_local(Expr $syntax) =>
  $saved_source($syntax);

keyword source_alias $imported.source;

int main(void) {
  printf("[%s]\n", $source(1+2));
  printf("[%s]\n", $source(1 + 2));
  printf("[%s]\n", $forward(
    (1 /* retained */ +
     2)
  ));
  printf("[%s]\n", $imported.source("a\\n"));
  printf("[%s]\n", source_alias((3)));
  printf("[%s]\n", $source_local(1 /* local */ + 2));
  return 0;
}
