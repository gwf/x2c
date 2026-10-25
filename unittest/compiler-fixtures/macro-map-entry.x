#include "x2c.x"

#include "macro-map-entry-import.x"

macro Entry $handler(Name $name) {
  $Code.binding_spelling($name): $name
}

macro Entry $two() {
  "left": 3,
  "right": 4,
}

macro Entry $none() {
}

macro Entry $forward(Entry @rows) {
  @rows
}

macro Entry $forward_one(Entry $row) {
  $row
}

macro Entry $nested_rows() {
  $two()
}

meta static List entry(String key, String value) {
  return %(map-entry
    (expr ("String")
      (segments (segexp (expr ("String") (literal ("String") $key)))))
    (expr (int) (literal (int) $value)));
}

meta static List built_entries(void) =>
  %(${entry("built-a", "7")} ${entry("built-b", "8")});

meta static String generated_key(void) => "generated-key";

macro Entry $built_rows() {
  @built_entries()
}

macro Expression $expression_key() => "expression";

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
    ${$built_rows()},
    ${$generated_key()}: 10,
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
    handlers["built-a"].integer(), handlers["built-b"].integer(),
    handlers["generated-key"].integer(),
    handlers["expression"].integer(),
    handlers["imported"].integer(),
    handlers["nested"].map()["left"].integer()
  );
  return 0;
}
