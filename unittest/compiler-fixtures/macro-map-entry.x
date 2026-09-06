#include "x2c.x"

$(import "macro-map-entry-import.xmacro")

macro Entry $handler(Name $name) => {
  $(x2c.literal.string (x2c.binding.spelling $name)): $name
}

macro Entry $two() => {
  "left": 3,
  "right": 4,
}

macro Entry $none() => {
}

macro Entry $forward(Entry $rows...) => {
  $rows...
}

macro Entry $forward_one(Entry $row) => {
  $row
}

macro Entry $nested_rows() => {
  $two()
}

macro Entry $lisp_rows() => {
  $(list
    (list 'map-entry (x2c.literal.string "lisp-a")
                     (x2c.literal.int 7))
    (list 'map-entry (x2c.literal.string "lisp-b")
                     (x2c.literal.int 8)))...
}

macro Expression $expression_key() => ("expression")

keyword pair $two;

int main(void) {
  int open = 1, close = 2;
  Map nested = %{ ${$nested_rows()} };
  Map handlers = %{
    ${$handler(open)},
    ${$handler(close)},
    ${$none()},
    ${pair()},
    ${$forward("forward-a": 5, "forward-b": 6)},
    ${$forward_one("forward-one": 12)},
    ${$lisp_rows()},
    ${$(x2c.literal.string "generated-key")}: 10,
    ${$expression_key()}: 11,
    "nested": $nested,
    ${$imported.row()},
  };
  printf(
    "%ld %ld %ld %ld %ld %ld %ld %ld %ld %ld %ld %ld %ld\n",
    handlers["open"].integer(), handlers["close"].integer(),
    handlers["left"].integer(), handlers["right"].integer(),
    handlers["forward-a"].integer(), handlers["forward-b"].integer(),
    handlers["forward-one"].integer(),
    handlers["lisp-a"].integer(), handlers["lisp-b"].integer(),
    handlers["generated-key"].integer(),
    handlers["expression"].integer(),
    handlers["imported"].integer(),
    handlers["nested"].map()["left"].integer()
  );
  return 0;
}
