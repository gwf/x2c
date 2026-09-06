#include "x2c.x"

static int calls;

static int answer(int value) {
  calls++;
  return value;
}

macro Expression $fixture.identity(Expr $value) => (
  $value
)

int main(void) {
  int base = 40;
  List tail = %(x y);
  List insert = %(answer ${answer(base) + 2});
  List splice = %(head @{tail} foot);
  List short_splice = %(head @tail foot);
  List nested = %(outer (inner ${base + 2}));
  List nested_string = %("answer=${base + 2}");
  List short_then_list = %($base(tail));
  int compile_time = $(+ 40 2);
  List nested_compile_time = %(${$(+ 40 2)});
  String text = %"answer=${base + 2}", short_then_text = %"$base()";
  Array array = %[${$(+ 40 2)}];
  Map map = %{answer: ${$(+ 40 2)}};
  int macro_value = $fixture.identity(base + 2), comma = 0;
  List comma_value = %(${comma = 1, (int) (comma + 1)});
  List index = %(${array[0].int()});
  List ternary = %(${base == 40 ? 42 : 0});
  List literals = %(
    ${%(inner 42)} ${%"answer=42"} ${%[42]} ${%{answer: 42}}
  );

  if (insert != %(answer 42) || splice != %(head x y foot)) return 1;
  if (short_splice != splice) return 2;
  if (nested != %(outer (inner 42))) return 3;
  if (nested_string[0].string() != %"answer=42") return 4;
  if (short_then_list != %(40 (tail))) return 5;
  if (compile_time != 42 || nested_compile_time != %(42)) return 6;
  if (text != %"answer=42") return 7;
  if (short_then_text != %"40()") return 8;
  if (array[0].int() != 42 || map[<answer>].int() != 42) return 9;
  if (macro_value != 42 || calls != 1) return 10;
  if (comma_value != %(2) || comma != 1) return 11;
  if (index != %(42) || ternary != %(42)) return 12;
  if (literals[0].list() != %(inner 42) ||
      literals[1].string() != %"answer=42" ||
      literals[2].array()[0].int() != 42 ||
      literals[3].map()[<answer>].int() != 42)
    return 13;
  printf("braced unquote ok\n");
  return 0;
}
