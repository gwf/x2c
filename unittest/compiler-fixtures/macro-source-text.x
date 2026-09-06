#include "x2c.x"

$(import "macro-source-text-import.xmacro")

macro Expression $source(Expr $syntax) => (
  $(x2c.literal.string (x2c.source.text $syntax))
)

macro Expression $forward(Expr $syntax) => (
  $source($syntax)
)

macro Expression $source_local(Expr $syntax) => (
  $(let ((saved $syntax))
    (x2c.literal.string (x2c.source.text saved)))
)

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
